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
        # Cloudflare Tunnel 환경에서는 https:// URI 형식이 가장 확실합니다.
        milvus_uri = f"https://{MILVUS_HOST}:{MILVUS_PORT}"
        print(f"🔄 Connecting to Milvus via Secure Tunnel: {milvus_uri}...")

        # [최종 패치] Cloudflare의 엄격한 gRPC 정책 통과를 위한 설정 ⭐
        connections.connect(
            alias="default",
            uri=milvus_uri,
            secure=True,
            server_name=MILVUS_HOST,
            server_hostname=MILVUS_HOST
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
            index_params = {"metric_type": "COSINE", "index_type": "IVF_FLAT", "params": {"nlist": 128}}
            collection.create_index(field_name="embedding", index_params=index_params)
            print("✅ Index created.")
        else:
            print(f"ℹ️ Collection '{COLLECTION_NAME}' already exists.")

        Collection(COLLECTION_NAME).load()
        print("✅ Milvus Connected & Collection Loaded!")

    except Exception as e:
        print(f"⚠️ Milvus Connection Failed! Error: {str(e)}")

@app.on_event("startup")
async def startup_event():
    try:
        print("🚀 System Update: v4.6 (Final Infra & Code Sync)")
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
            return resp.json().get("embedding", []) if resp.status_code == 200 else []
        except Exception as e:
            print(f"Embedding Error: {e}"); return []

async def get_summary(text: str):
    prompt = f"아래 문서를 한 문장(50자 이내)으로 요약해줘:\n\n{text[:2000]}"
    async with httpx.AsyncClient(timeout=120.0) as client:
        try:
            resp = await client.post(f"{OLLAMA_URL}/api/generate",
                                     json={"model": LLM_MODEL, "prompt": prompt, "stream": False})
            return resp.json().get("response", "요약본 없음") if resp.status_code == 200 else "실패"
        except Exception as e:
            print(f"Summary Error: {e}"); return "에러"

@app.get("/health")
def health_check(): return {"status": "ok"}

@app.get("/")
def root(): return {"status": "ok", "message": "PBS AI Backend Running"}

@app.post("/api/upload")
async def upload_file(file: UploadFile = File(...)):
    try:
        content = await file.read()
        try:
            text_content = content.decode("utf-8")
        except UnicodeDecodeError:
            s3_client.put_object(Bucket=S3_BUCKET, Key=file.filename, Body=content)
            return {"message": "Binary Success", "filename": file.filename, "summary": "분석 불가"}

        s3_client.put_object(Bucket=S3_BUCKET, Key=file.filename, Body=content)
        summary = await get_summary(text_content)
        vector = await get_embedding(text_content)

        if vector and connections.has_connection("default"):
            collection = Collection(COLLECTION_NAME)
            collection.insert([[vector], [text_content], [file.filename], [summary]])
            collection.flush()
            print(f"✅ indexed: {file.filename}")

        return {"message": "Success", "filename": file.filename, "summary": summary}
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/chat")
async def chat(request: QueryRequest):
    try:
        query_vector = await get_embedding(request.query)
        if not query_vector: return {"answer": "엔진 연결 실패"}
        if not connections.has_connection("default"): init_milvus()

        collection = Collection(COLLECTION_NAME)
        collection.load()
        results = collection.search(
            data=[query_vector], anns_field="embedding",
            param={"metric_type": "COSINE", "params": {"nprobe": 10}},
            limit=3, output_fields=["text"]
        )

        context = "\n\n".join([hit.entity.get("text") for hits in results for hit in hits]) if results else ""
        if not context: return {"answer": "관련 문서 없음"}

        async with httpx.AsyncClient(timeout=120.0) as client:
            resp = await client.post(f"{OLLAMA_URL}/api/generate",
                                     json={"model": LLM_MODEL, "prompt": f"문서 바탕 답변: {context}\n질문: {request.query}", "stream": False})
            return {"answer": resp.json().get("response", "오류"), "context": context}
    except Exception as e: return {"answer": f"에러: {str(e)}"}

@app.get("/api/documents")
def list_documents():
    try:
        response = s3_client.list_objects_v2(Bucket=S3_BUCKET)
        return [{"id": i, "title": obj['Key'], "filename": obj['Key'], "date": obj['LastModified'].strftime("%Y-%m-%d"), "summary": "완료"}
                for i, obj in enumerate(response.get('Contents', []))]
    except Exception as e: return []

@app.get("/api/download/{filename}")
def download_file(filename: str):
    try:
        file_obj = s3_client.get_object(Bucket=S3_BUCKET, Key=filename)
        return Response(content=file_obj['Body'].read(), media_type="application/octet-stream")
    except Exception as e: raise HTTPException(status_code=404)