#FROM ollama/ollama
#EXPOSE 11434
#ENTRYPOINT ["/bin/ollama", "serve"]
#---------------------------------------------

FROM python:3.9-slim

WORKDIR /app
COPY on-prem/main.py .
# 통신에 필요한 라이브러리 설치
RUN pip install fastapi uvicorn httpx pydantic

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "80"]