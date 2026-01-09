import os
import time
from fastapi import FastAPI, HTTPException, UploadFile, File
from pydantic import BaseModel
import httpx
import boto3
from botocore.exceptions import ClientError
from pymilvus import connections, Collection, FieldSchema, CollectionSchema, DataType, utility

app = FastAPI()

# =========================================================
# 1. 환경 설정 (IRSA 및 K8s Env 활용)
# =========================================================
OLLAMA_URL = os.getenv("OLLAMA_URL", "https://api.cloudreaminu.cloud")  # 터널 주소로 기본값 변경
MILVUS_HOST = os.getenv("MILVUS_HOST", "milvus-standalone")  # 실제 서비스명으로 변경
MILVUS_PORT = "19530"
S3_BUCKET = os.getenv("S3_BUCKET_NAME", "pbs-project-ai-data-dev-v1")
AWS_REGION = "ap-northeast-2"

EMBEDDING_MODEL = "mxbai-embed-large"
LLM_MODEL = "solar:10.7b"

# =========================================================
# 2. 연결 초기화 (S3 & Milvus)
# =========================================================
# IRSA 덕분에 Access Key 없이 boto3가 자동으로 임시 토큰을 사용합니다.
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
                # [추가] 목록에서 보여줄 요약 필드
                FieldSchema(name="summary", dtype=DataType.VARCHAR, max_length=1024)
            ]
            schema = CollectionSchema(fields, "PBS Project Documents")
            Collection(collection_name, schema)
            index_params = {"metric_type": "COSINE", "index_type": "IVF_FLAT", "params": {"nlist": 128}}
            Collection(collection_name).create_index(field_name="embedding", index_params=index_params)
            print("✅ Milvus Collection Created with Summary field!")

        Collection(collection_name).load()
        print("✅ Milvus Connected!")
    except Exception as e:
        print(f"⚠️ Milvus Error: {e}")


@app.on_event("startup")
async def startup_event():
    time.sleep(5)
    init_milvus()


# =========================================================
# 3. 헬퍼 함수: AI 호출 (Ollama)
# =========================================================
async def get_embedding(text: str):
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.post(f"{OLLAMA_URL}/api/embeddings", json={"model": EMBEDDING_MODEL, "prompt": text})
            return resp.json()["embedding"]
        except:
            return []


async def get_summary(text: str):
    # [추가] 업로드 시 자동으로 1문장 요약 생성
    prompt = f"아래 문서를 한 문장(50자 이내)으로 요약해줘:\n\n{text[:2000]}"
    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            resp = await client.post(f"{OLLAMA_URL}/api/generate",
                                     json={"model": LLM_MODEL, "prompt": prompt, "stream": False})
            return resp.json().get("response", "요약본 없음")
        except:
            return "요약 생성 실패"


# =========================================================
# 4. API 엔드포인트
# =========================================================

@app.get("/")
def health_check():
    return {"status": "ok", "backend": "PBS AI Hybrid"}


# [업로드] S3 저장 + 요약 생성 + Milvus 저장
@app.post("/api/upload")
async def upload_file(file: UploadFile = File(...)):
    try:
        content = await file.read()
        text_content = content.decode("utf-8")  # PDF 대응은 추후 PyMuPDF 추가 권장

        # 1. S3 저장
        s3_client.put_object(Bucket=S3_BUCKET, Key=file.filename, Body=content)

        # 2. 요약 및 임베딩 생성 (AI 호출)
        summary = await get_summary(text_content)
        vector = await get_embedding(text_content)

        # 3. Milvus 저장
        collection = Collection("pbs_docs")
        collection.insert([
            [vector], [text_content], [file.filename], [summary]
        ])
        collection.flush()

        return {"message": "Success", "summary": summary}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# [문서 목록] S3 파일 리스트 + 다운로드용 Presigned URL 생성
@app.get("/api/documents")
def list_documents():
    try:
        response = s3_client.list_objects_v2(Bucket=S3_BUCKET)
        docs = []
        if 'Contents' in response:
            for i, obj in enumerate(response['Contents']):
                # [핵심] 다운로드용 임시 URL 생성 (1시간 유효)
                presigned_url = s3_client.generate_presigned_url(
                    'get_object',
                    Params={'Bucket': S3_BUCKET, 'Key': obj['Key']},
                    ExpiresIn=3600
                )

                docs.append({
                    "id": i,
                    "title": obj['Key'],
                    "url": presigned_url,  # 프론트엔드에서 <a> 태그에 넣을 주소
                    "date": obj['LastModified'].strftime("%Y-%m-%d"),
                    "summary": "AI 분석이 완료된 문서입니다."  # Milvus와 연동 시 실제 요약 출력 가능
                })
        return docs
    except Exception as e:
        return {"error": str(e)}


@app.post("/api/chat")
async def chat(request: QueryRequest):
    # (기존 chat 로직과 동일하되, 프롬프트만 하이브리드 최적화 유지)
    ...