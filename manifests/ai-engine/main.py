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
COLLECTION_NAME = "pbs_docs"

s3_client = boto3.client("s3", region_name=AWS_REGION)

def init_milvus():
    """Milvus 연결 및 컬렉션 초기화 (수정됨: 중복 생성 에러 방지)"""
    try:
        print(f"🔄 Connecting to Milvus at {MILVUS_HOST}:{MILVUS_PORT}...")
        connections.connect("default", host=MILVUS_HOST, port=MILVUS_PORT)
        
        # [수정 1] 컬렉션이 없을 때만 생성하도록 분기 처리
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
            
            # 인덱스 생성 (생성 직후 바로 수행)
            index_params = {
                "metric_type": "COSINE", 
                "index_type": "IVF_FLAT", 
                "params": {"nlist": 128}
            }
            collection.create_index(field_name="embedding", index_params=index_params)
            print("✅ Index created.")
        else:
            print(f"ℹ️ Collection '{COLLECTION_NAME}' already exists.")

        # [수정 1] 마지막에 확실하게 로드
        Collection(COLLECTION_NAME).load()
        print("✅ Milvus Connected & Collection Loaded!")
        
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
            resp = await client.post(
                f"{OLLAMA_URL}/api/embeddings", 
                json={"model": EMBEDDING_MODEL, "prompt": text},
                timeout=10.0
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
        
        # [수정 2] 텍스트 파일이 아닌 경우(이미지 등) 업로드만 하고 분석은 스킵
        try:
            text_content = content.decode("utf-8")
        except UnicodeDecodeError:
            # 텍스트가 아니면 S3에만 올리고 종료
            s3_client.put_object(Bucket=S3_BUCKET, Key=file.filename, Body=content)
            return {"message": "Success (Binary File)", "filename": file.filename, "summary": "분석 불가 (텍스트 아님)"}

        # S3 업로드
        s3_client.put_object(Bucket=S3_BUCKET, Key=file.filename, Body=content)
        
        summary = "요약 대기중"
        try:
            summary = await get_summary(text_content)
            vector = await get_embedding(text_content)
            
            # [수정 3] Milvus 데이터 삽입 구조 명확화
            if vector and connections.has_connection("default"):
                collection = Collection(COLLECTION_NAME)
                # 데이터 구조: [ [col1_list], [col2_list], ... ]
                data = [
                    [vector],       # embedding
                    [text_content], # text
                    [file.filename],# filename
                    [summary]       # summary
                ]
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
        
        collection = Collection(COLLECTION_NAME)
        # 로드가 안 되어 있을 경우 대비
        collection.load()
        
        results = collection.search(
            data=[query_vector], anns_field="embedding",
            param={"metric_type": "COSINE", "params": {"nprobe": 10}},
            limit=3, output_fields=["text"]
        )
        
        # 검색 결과 조합
        context_texts = []
        if results:
            for hits in results:
                for hit in hits:
                    context_texts.append(hit.entity.get("text"))
        
        context = "\n\n".join(context_texts) if context_texts else ""
        
        if not context:
            return {"answer": "관련된 문서를 찾을 수 없습니다.", "context": ""}
        
        async with httpx.AsyncClient(timeout=60.0) as client:
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
        
        # [수정 4] 다운로드 시 디코딩 에러 방지 (바이너리 파일 처리)
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