import requests
import os

# 백엔드 주소 (Ingress 주소 또는 로컬 포트포워딩 주소)
API_URL = "http://soldesk-group4-pbs-project.click/api/upload"
# API_URL = "http://localhost:8000/api/upload" # 로컬 테스트 시

DOCS_DIR = "./sample_docs"

def upload_docs():
    if not os.path.exists(DOCS_DIR):
        print(f"❌ '{DOCS_DIR}' 폴더가 없습니다. 텍스트 파일을 먼저 만들어주세요.")
        return

    for filename in os.listdir(DOCS_DIR):
        file_path = os.path.join(DOCS_DIR, filename)
        
        if os.path.isfile(file_path):
            print(f"📤 업로드 중: {filename} ...")
            try:
                with open(file_path, "rb") as f:
                    files = {"file": (filename, f, "text/plain")}
                    response = requests.post(API_URL, files=files)
                
                if response.status_code == 200:
                    print(f"✅ 성공: {response.json()['message']}")
                else:
                    print(f"❌ 실패: {response.text}")
            except Exception as e:
                print(f"🚨 에러 발생: {e}")

if __name__ == "__main__":
    upload_docs()