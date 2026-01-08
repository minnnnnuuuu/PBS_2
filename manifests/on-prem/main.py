from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import httpx

app = FastAPI()

# Ollama 주소 (쿠버네티스 서비스 이름)
OLLAMA_URL = "http://ollama-service:11434/api/generate"

class QueryRequest(BaseModel):
    query: str

@app.get("/")
def health_check():
    return {"status": "ok", "message": "Backend is running!"}

@app.post("/api/chat")
async def chat(request: QueryRequest):
    try:
        # Ollama에게 질문 전달
        payload = {
            "model": "solar:10.7b",  # 사용할 모델 이름
            "prompt": request.query,
            "stream": False
        }
        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(OLLAMA_URL, json=payload)
            response.raise_for_status()
            
        return {"answer": response.json().get("response", "")}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))