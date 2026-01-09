import os
import time
import httpx
import boto3
from fastapi import FastAPI, HTTPException, UploadFile, File
from pydantic import BaseModel
from pymilvus import connections, Collection, FieldSchema, CollectionSchema, DataType, utility

app = FastAPI()

# =========================================================
# 1. 환경 설정
# =========================================================
OLLAMA_URL = os.getenv("OLLAMA_URL", "https://api.cloudreaminu.cloud")
MILVUS_HOST = os.getenv("MILVUS_HOST", "milvus-standalone")
MILVUS_PORT = "19530"
S3_BUCKET = os.getenv("S3_BUCKET_NAME", "pbs-project-ai-data-dev-v1")
AWS_REGION = "ap-northeast-2"

EMBEDDING_MODEL = "mxbai-embed-large"
LLM_MODEL = "solar:10.7b"

# =========================================================
# 2. 연결 초기화 (S3 & Milvus)
# =========================================================
s3_client = boto3.client("s3", region_name=AWS_REGION)


def init_milvus():
    try:
        connections.connect("default", host=MILVUS_HOST, port=MILVUS_PORT)
        collection_name = "pbs_docs"
        if not utility.has_collection(collection_name):
            fields = [
                FieldSchema(name="id", dtype=DataType.INT64, is_primary=True, auto_id=True),
                FieldSchema(name="embedding", dtype=DataType.FLOAT_VECTOR, dim=1024),
                FieldSchema(name="text", dtype=DataType.VARCHAR, max_length=65535),
                FieldSchema(name="filename", dtype=DataType.VARCHAR, max_length=512),
                FieldSchema(name="summary", dtype=DataType.VARCHAR, max_length=1024)
            ]
            schema = CollectionSchema(fields, "PBS Project Documents")
            Collection(collection_name, schema)
            index_params = {"metric_type": "COSINE", "index_type": "IVF_FLAT", "params": {"nlist": 128}}
            Collection(collection_name).create_index(field_name="embedding", index_params=index_params)
        Collection(collection_name).load()
        print("✅ Milvus Connected!")
    except Exception as e:
        print(f"⚠️ Milvus Connection Failed: {e}")


@app.on_event("startup")
async def startup_event():
    time.sleep(5)
    init_milvus()


# =========================================================
# 3. 데이터 모델 및 헬퍼 함수
# =========================================================
class QueryRequest(BaseModel):
    query: str


async def get_embedding(text: str):
    """지정된 텍스트의 임베딩 벡터를 가져옵니다 (Line 66 경고 해결)"""
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.post(f"{OLLAMA_URL}/api/embeddings", json={"model": EMBEDDING_MODEL, "prompt": text})
            resp.raise_for_status()
            return resp.json().get("embedding", [])
        except Exception as e:
            print(f"Embedding Error: {e}")
            return []  # 에러 발생 시 반드시 리스트를 반환하여 66번 경고를 해결함


async def get_summary(text: str):
    """텍스트 요약을 생성합니다 (Line 79 경고 해결)"""
    prompt = f"아래 문서를 한 문장(50자 이내)으로 요약해줘:\n\n{text[:2000]}"
    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            resp = await client.post(f"{OLLAMA_URL}/api/generate",
                                     json={"model": LLM_MODEL, "prompt": prompt, "stream": False})
            resp.raise_for_status()
            return resp.json().get("response", "요약본 없음")
        except Exception as e:
            print(f"Summary Error: {e}")
            return "요약 생성 실패"  # 에러 발생 시 반드시 문자열을 반환하여 79번 경고를 해결함


# =========================================================
# 4. API 엔드포인트
# =========================================================

@app.get("/")
def health_check():
    return {"status": "ok", "message": "PBS AI Backend Running"}


@app.post("/api/upload")
async def upload_file(file: UploadFile = File(...)):
    try:
        content = await file.read()
        text_content = content.decode("utf-8")

        # 1. S3 저장
        s3_client.put_object(Bucket=S3_BUCKET, Key=file.filename, Body=content)

        # 2. AI 분석
        summary = await get_summary(text_content)
        vector = await get_embedding(text_content)

        # 3. Milvus 저장
        if vector:
            collection = Collection("pbs_docs")
            collection.insert([[vector], [text_content], [file.filename], [summary]])
            collection.flush()

        return {"message": "Success", "filename": file.filename, "summary": summary}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/chat")
async def chat(request: QueryRequest):
    query_vector = await get_embedding(request.query)
    if not query_vector:
        return {"answer": "AI 엔진 연결 실패"}

    collection = Collection("pbs_docs")
    # nprobe는 Milvus 전용 파라미터로 오타가 아닙니다.
    results = collection.search(
        data=[query_vector],
        anns_field="embedding",
        param={"metric_type": "COSINE", "params": {"nprobe": 10}},
        limit=3,
        output_fields=["text"]
    )

    context = "\n".join([hit.entity.get("text") for hit in results[0]]) if results else ""

    async with httpx.AsyncClient(timeout=60.0) as client:
        payload = {
            "model": LLM_MODEL,
            "prompt": f"문서내용:\n{context}\n\n질문: {request.query}",
            "stream": False
        }
        resp = await client.post(f"{OLLAMA_URL}/api/generate", json=payload)
        answer = resp.json().get("response", "답변 불가")
        return {"answer": answer, "context": context}


@app.get("/api/documents")
def list_documents():
    """문서 목록과 Presigned URL을 반환합니다 (Line 141 경고 해결)"""
    try:
        response = s3_client.list_objects_v2(Bucket=S3_BUCKET)
        docs = []
        if 'Contents' in response:
            for i, obj in enumerate(response['Contents']):
                url = s3_client.generate_presigned_url(
                    'get_object', Params={'Bucket': S3_BUCKET, 'Key': obj['Key']}, ExpiresIn=3600
                )
                docs.append({
                    "id": i, "title": obj['Key'], "url": url,
                    "date": obj['LastModified'].strftime("%Y-%m-%d"),
                    "summary": "AI 분석 완료"
                })
        return docs
    except Exception as e:
        print(f"S3 List Error: {e}")
        return []  # 에러 발생 시 빈 리스트를 반환하여 141번 경고를 해결함