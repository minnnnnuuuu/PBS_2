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
MILVUS_HOST = os.getenv("MILVUS_HOST", "milvus-standalone")
MILVUS_PORT = "19530"
S3_BUCKET = os.getenv("S3_BUCKET_NAME", "pbs-project-ai-data-dev-v1")
AWS_REGION = "ap-northeast-2"

EMBEDDING_MODEL = "mxbai-embed-large"
LLM_MODEL = "solar:10.7b"

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
    try:
        time.sleep(5)
        init_milvus()
    except Exception as e:
        print(f"Startup Warning: {e}")

class QueryRequest(BaseModel):
    query: str

async def get_embedding(text: str):
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.post(f"{OLLAMA_URL}/api/embeddings", json={"model": EMBEDDING_MODEL, "prompt": text})
            if resp.status_code != 200: return []
            return resp.json().get("embedding", [])
        except Exception as e:
            print(f"Embedding Error: {e}")
            return []

async def get_summary(text: str):
    prompt = f"아래 문서를 한 문장(50자 이내)으로 요약해줘:\n\n{text[:2000]}"
    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            resp = await client.post(f"{OLLAMA_URL}/api/generate",
                                     json={"model": LLM_MODEL, "prompt": prompt, "stream": False})
            if resp.status_code != 200: return "요약 생성 실패"
            return resp.json().get("response", "요약본 없음")
        except Exception as e:
            print(f"Summary Error: {e}")
            return "요약 생성 실패"

@app.get("/")
def health_check():
    return {"status": "ok", "message": "PBS AI Backend Running"}

@app.post("/api/upload")
async def upload_file(file: UploadFile = File(...)):
    try:
        content = await file.read()
        text_content = content.decode("utf-8")
        s3_client.put_object(Bucket=S3_BUCKET, Key=file.filename, Body=content)
        
        summary = "요약 대기중"
        try:
            summary = await get_summary(text_content)
            vector = await get_embedding(text_content)
            if vector and connections.has_connection("default"):
                collection = Collection("pbs_docs")
                collection.insert([[vector], [text_content], [file.filename], [summary]])
                collection.flush()
        except Exception:
            pass
        return {"message": "Success", "filename": file.filename, "summary": summary}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/chat")
async def chat(request: QueryRequest):
    try:
        query_vector = await get_embedding(request.query)
        if not query_vector: return {"answer": "AI 엔진 연결 실패"}
        
        collection = Collection("pbs_docs")
        results = collection.search(
            data=[query_vector], anns_field="embedding",
            param={"metric_type": "COSINE", "params": {"nprobe": 10}},
            limit=3, output_fields=["text"]
        )
        context = "\n".join([hit.entity.get("text") for hit in results[0]]) if results else ""
        
        async with httpx.AsyncClient(timeout=60.0) as client:
            resp = await client.post(f"{OLLAMA_URL}/api/generate", 
                json={"model": LLM_MODEL, "prompt": f"문서내용:\n{context}\n\n질문: {request.query}", "stream": False})
            answer = resp.json().get("response", "답변 불가")
            return {"answer": answer, "context": context}
    except Exception as e:
        print(f"Chat Error: {e}")
        return {"answer": "AI 서비스 점검 중입니다.", "context": ""}

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
        content = file_obj['Body'].read().decode('utf-8')
        return Response(content=content, media_type="text/plain")
    except Exception as e:
        print(f"Download Error: {e}")
        raise HTTPException(status_code=404, detail="File not found in S3")