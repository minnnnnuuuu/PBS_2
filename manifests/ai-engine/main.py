import os
import time
from fastapi import FastAPI, HTTPException, UploadFile, File
from pydantic import BaseModel
import httpx
import boto3
from pymilvus import connections, Collection, FieldSchema, CollectionSchema, DataType, utility

app = FastAPI()

# =========================================================
# 1. 환경 설정 (Kubernetes Env에서 주입받음)
# =========================================================
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://ollama-service:11434")
MILVUS_HOST = os.getenv("MILVUS_HOST", "milvus-service") # K8s 서비스 이름
MILVUS_PORT = "19530"
S3_BUCKET = os.getenv("S3_BUCKET_NAME", "pbs-project-data-dev-v1")
AWS_REGION = "ap-northeast-2"

# 모델 설정
EMBEDDING_MODEL = "mxbai-embed-large" # 임베딩용 (Ollama에 이 모델도 pull 해야 함)
LLM_MODEL = "solar:10.7b"             # 답변용

# =========================================================
# 2. 연결 초기화 (S3 & Milvus)
# =========================================================
s3_client = boto3.client("s3", region_name=AWS_REGION)

# Milvus 연결 및 컬렉션(테이블) 생성
def init_milvus():
    try:
        connections.connect("default", host=MILVUS_HOST, port=MILVUS_PORT)
        
        collection_name = "pbs_docs"
        if not utility.has_collection(collection_name):
            # 스키마 정의: ID, 임베딩벡터, 원래텍스트, 파일명
            fields = [
                FieldSchema(name="id", dtype=DataType.INT64, is_primary=True, auto_id=True),
                FieldSchema(name="embedding", dtype=DataType.FLOAT_VECTOR, dim=1024), # mxbai 모델 차원수(보통 1024)
                FieldSchema(name="text", dtype=DataType.VARCHAR, max_length=65535),
                FieldSchema(name="filename", dtype=DataType.VARCHAR, max_length=512)
            ]
            schema = CollectionSchema(fields, "PBS Project Documents")
            Collection(collection_name, schema)
            # 인덱스 생성 (검색 속도 향상)
            index_params = {"metric_type": "COSINE", "index_type": "IVF_FLAT", "params": {"nlist": 128}}
            Collection(collection_name).create_index(field_name="embedding", index_params=index_params)
            print("✅ Milvus Collection Created!")
        
        # 컬렉션 메모리에 로드 (검색 준비)
        Collection(collection_name).load()
        print("✅ Milvus Connected & Loaded!")
    except Exception as e:
        print(f"⚠️ Milvus Connection Failed: {e}")

# 앱 시작 시 DB 연결 시도
@app.on_event("startup")
async def startup_event():
    # Milvus가 뜰 때까지 잠시 대기
    time.sleep(5) 
    init_milvus()

# =========================================================
# 3. 헬퍼 함수: Ollama에게 "텍스트 -> 벡터" 변환 요청
# =========================================================
async def get_embedding(text: str):
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.post(
                f"{OLLAMA_URL}/api/embeddings",
                json={"model": EMBEDDING_MODEL, "prompt": text}
            )
            resp.raise_for_status()
            return resp.json()["embedding"]
        except Exception as e:
            print(f"Embedding Error: {e}")
            return []

# =========================================================
# 4. API 엔드포인트
# =========================================================

class QueryRequest(BaseModel):
    query: str

@app.get("/")
def health_check():
    return {"status": "ok", "message": "PBS AI Backend Running"}

# [검색 + 답변] 사용자가 질문하면 실행됨
@app.post("/api/chat")
async def chat(request: QueryRequest):
    # 1. 질문을 벡터로 변환
    query_vector = await get_embedding(request.query)
    if not query_vector:
        return {"answer": "임베딩 모델 오류가 발생했습니다."}

    # 2. Milvus에서 유사한 문서 검색
    collection = Collection("pbs_docs")
    results = collection.search(
        data=[query_vector], 
        anns_field="embedding", 
        param={"metric_type": "COSINE", "params": {"nprobe": 10}}, 
        limit=3, # 가장 비슷한 문서 3개만 가져옴
        output_fields=["text"]
    )

    # 3. 검색된 문서 내용 합치기 (Context)
    found_text = "\n".join([hit.entity.get("text") for hit in results[0]])
    
    # 4. 프롬프트 조립
    system_prompt = f"""
    당신은 기술 문서 전문가입니다. 아래 [참고 문서]를 바탕으로 사용자의 질문에 답변하세요.
    문서에 없는 내용은 지어내지 말고 모른다고 하세요.
    
    [참고 문서]
    {found_text}
    """
    
    # 5. LLM에게 답변 요청
    payload = {
        "model": LLM_MODEL,
        "prompt": f"{system_prompt}\n\n[질문]: {request.query}",
        "stream": False
    }
    
    async with httpx.AsyncClient(timeout=60.0) as client:
        response = await client.post(f"{OLLAMA_URL}/api/generate", json=payload)
        return {"answer": response.json().get("response", ""), "context": found_text}

# [문서 업로드] 초기 데이터 넣을 때 사용
@app.post("/api/upload")
async def upload_file(file: UploadFile = File(...)):
    try:
        # 1. 파일 내용 읽기 (여기선 텍스트 파일 가정, PDF는 추가 라이브러리 필요)
        content = await file.read()
        text_content = content.decode("utf-8") # PDF라면 여기서 pdf parsing 로직 필요
        
        # 2. S3에 원본 저장
        s3_client.put_object(Bucket=S3_BUCKET, Key=file.filename, Body=content)
        
        # 3. 텍스트 -> 벡터 변환
        vector = await get_embedding(text_content)
        
        # 4. Milvus에 저장
        collection = Collection("pbs_docs")
        collection.insert([
            [vector],       # embedding
            [text_content], # text
            [file.filename] # filename
        ])
        collection.flush() # 저장 확정
        
        return {"message": f"{file.filename} 처리 완료! S3 업로드 및 Vector DB 저장 성공."}
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
@app.get("/api/documents")
def list_documents():
    try:
        response = s3_client.list_objects_v2(Bucket=S3_BUCKET)
        docs = []
        if 'Contents' in response:
            for i, obj in enumerate(response['Contents']):
                docs.append({
                    "id": i,
                    "title": obj['Key'], # 파일명
                    "type": obj['Key'].split('.')[-1], # 확장자
                    "date": obj['LastModified'].strftime("%Y-%m-%d"),
                    "vendor": "Vendor", # 메타데이터가 없으면 임시값
                    "summary": "서버에 저장된 문서입니다."
                })
        return docs
    except Exception as e:
        print(f"S3 Error: {e}")
        return []