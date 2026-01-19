import os
import time
import httpx
import boto3
from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.responses import Response
from pydantic import BaseModel
from pymilvus import connections, Collection, FieldSchema, CollectionSchema, DataType, utility

app = FastAPI()

# =========================================================
# 1. 환경 설정
# =========================================================
OLLAMA_URL = os.getenv("OLLAMA_URL", "https://api.cloudreaminu.cloud")

# [수정] 환경 변수 읽기 안정화
MILVUS_HOST = os.getenv("MILVUS_HOST", "milvus.cloudreaminu.cloud")
MILVUS_PORT = os.getenv("MILVUS_PORT", "443")

S3_BUCKET = os.getenv("S3_BUCKET_NAME", "pbs-project-ai-data-dev-v1")
AWS_REGION = "ap-northeast-2"

EMBEDDING_MODEL = "mxbai-embed-large"
LLM_MODEL = "solar:10.7b"
COLLECTION_NAME = "pbs_docs"

s3_client = boto3.client("s3", region_name=AWS_REGION)


def init_milvus():
    """Milvus 연결 및 컬렉션 초기화"""
    try:
        # 443 포트 사용 시에는 반드시 https:// 를 포함한 URI 방식이 가장 안정적입니다.
        milvus_uri = f"https://{MILVUS_HOST}:{MILVUS_PORT}"
        print(f"🔄 Connecting to Milvus via Secure Tunnel: {milvus_uri}...")

        # [최종 해결 포인트] Cloudflare gRPC 프록시는 SNI(Server Name Indication) 정보가
        # 명확하지 않으면 연결을 즉시 차단합니다. 이를 위해 server_hostname을 추가합니다. ⭐
        connections.connect(
            alias="default",
            uri=milvus_uri,
            secure=True,
            server_name=MILVUS_HOST,
            server_hostname=MILVUS_HOST  # Cloudflare가 gRPC 패킷을 인식하게 하는 핵심 옵션
        )

        if not utility.has_collection(COLLECTION_NAME):
            print(f"🆕 Creating collection: {COLLECTION_NAME}")
            fields = [
                FieldSchema(name="id", dtype=DataType.INT64, is_primary=True, auto_id=True),
                FieldSchema(name="embedding", dtype=DataType.FLOAT_VECTOR, dim=1024),
                FieldSchema(name="text", dtype=DataType.VARCHAR, max_length=65535),
                FieldSchema(name="filename", dtype=DataType.VARCHAR, max_length=512),
                FieldSchema(name="summary", dtype=DataType.VARCHAR, max_length=1024)
            ]
            schema = CollectionSchema(fields, "PBS Project Documents")
            collection = Collection(COLLECTION_NAME, schema)

            index_params = {
                "metric_type": "COSINE",
                "index_type": "IVF_FLAT",
                "params": {"nlist": 128}
            }
            collection.create_index(field_name="embedding", index_params=index_params)
            print("✅ Index created.")
        else:
            print(f"ℹ️ Collection '{COLLECTION_NAME}' already exists.")

        # 컬렉션을 메모리에 로드
        Collection(COLLECTION_NAME).load()
        print("✅ Milvus Connected & Collection Loaded!")

    except Exception as e:
        print(f"⚠️ Milvus Connection Failed: {e}")


@app.on_event("startup")
async def startup_event():
    try:
        print("🚀 System Update: v4.3 (Final gRPC Patch Applied)")
        # 터널 연결이 완전히 확립될 때까지 대기 시간을 조금 더 가집니다.
        time.sleep(10)
        init_milvus()
    except Exception as e:
        print(f"Startup Warning: {e}")


class QueryRequest(BaseModel):
    query: str


async def get_embedding(text: str):
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.post(
                f"{OLLAMA_URL}/api/embeddings",
                json={"model": EMBEDDING_MODEL, "prompt": text},
                timeout=60.0
            )
            if resp.status_code != 200:
                print(f"Embedding API Error: {resp.status_code}")
                return []
            return resp.json().get("embedding", [])
        except Exception as e:
            print(f"Embedding Error: {e}")
            return []


async def get_summary(text: str):
    prompt = f"아래 문서를 한 문장(50자 이내)으로 요약해줘:\n\n{text[:2000]}"
    async with httpx.AsyncClient(timeout=120.0) as client:
        try:
            resp = await client.post(f"{OLLAMA_URL}/api/generate",
                                     json={"model": LLM_MODEL, "prompt": prompt, "stream": False})
            if resp.status_code != 200: return "요약 생성 실패"
            return resp.json().get("response", "요약본 없음")
        except Exception as e:
            print(f"Summary Error: {e}")
            return "요약 생성 실패"


@app.get("/health")
def health_check():
    return {"status": "ok"}


@app.get("/")
def root():
    return {"status": "ok", "message": "PBS AI Backend Running"}


@app.post("/api/upload")
async def upload_file(file: UploadFile = File(...)):
    try:
        content = await file.read()
        try:
            text_content = content.decode("utf-8")
        except UnicodeDecodeError:
            s3_client.put_object(Bucket=S3_BUCKET, Key=file.filename, Body=content)
            return {"message": "Success (Binary File)", "filename": file.filename, "summary": "분석 불가 (텍스트 아님)"}

        s3_client.put_object(Bucket=S3_BUCKET, Key=file.filename, Body=content)

        summary = "요약 대기중"
        try:
            summary = await get_summary(text_content)
            vector = await get_embedding(text_content)

            if vector and connections.has_connection("default"):
                collection = Collection(COLLECTION_NAME)
                data = [[vector], [text_content], [file.filename], [summary]]
                collection.insert(data)
                collection.flush()
                print(f"✅ Document '{file.filename}' indexed.")
        except Exception as e:
            print(f"⚠️ Indexing Error: {e}")
            pass

        return {"message": "Success", "filename": file.filename, "summary": summary}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/chat")
async def chat(request: QueryRequest):
    try:
        query_vector = await get_embedding(request.query)
        if not query_vector: return {"answer": "AI 엔진 연결 실패 (임베딩 불가)"}

        if not connections.has_connection("default"):
            init_milvus()

        collection = Collection(COLLECTION_NAME)
        collection.load()

        results = collection.search(
            data=[query_vector], anns_field="embedding",
            param={"metric_type": "COSINE", "params": {"nprobe": 10}},
            limit=3, output_fields=["text"]
        )

        context_texts = []
        if results:
            for hits in results:
                for hit in hits:
                    context_texts.append(hit.entity.get("text"))

        context = "\n\n".join(context_texts) if context_texts else ""
        if not context:
            return {"answer": "관련된 문서를 찾을 수 없습니다.", "context": ""}

        async with httpx.AsyncClient(timeout=120.0) as client:
            resp = await client.post(f"{OLLAMA_URL}/api/generate",
                                     json={
                                         "model": LLM_MODEL,
                                         "prompt": f"다음 문서를 바탕으로 질문에 답변해줘.\n\n[문서내용]:\n{context}\n\n[질문]: {request.query}\n\n[답변]:",
                                         "stream": False
                                     }
                                     )
            answer = resp.json().get("response", "답변 생성 실패")
            return {"answer": answer, "context": context}

    except Exception as e:
        print(f"Chat Error: {e}")
        return {"answer": f"에러가 발생했습니다: {str(e)}", "context": ""}


@app.get("/api/documents")
def list_documents():
    try:
        response = s3_client.list_objects_v2(Bucket=S3_BUCKET)
        docs = []
        if 'Contents' in response:
            for i, obj in enumerate(response['Contents']):
                docs.append({
                    "id": i, "title": obj['Key'], "filename": obj['Key'],
                    "date": obj['LastModified'].strftime("%Y-%m-%d"), "summary": "AI 분석 완료"
                })
        return docs
    except Exception as e:
        print(f"S3 List Error: {e}")
        return []


@app.get("/api/download/{filename}")
def download_file(filename: str):
    try:
        file_obj = s3_client.get_object(Bucket=S3_BUCKET, Key=filename)
        content = file_obj['Body'].read()
        try:
            decoded_content = content.decode('utf-8')
            return Response(content=decoded_content, media_type="text/plain")
        except UnicodeDecodeError:
            return Response(
                content=content,
                media_type="application/octet-stream",
                headers={"Content-Disposition": f"attachment; filename={filename}"}
            )
    except Exception as e:
        print(f"Download Error: {e}")
        raise HTTPException(status_code=404, detail="File not found in S3")