import boto3
import os
from dotenv import load_dotenv

# .env 파일에서 환경 변수 로드 (없으면 수동으로 설정 가능)
load_dotenv()

# S3 설정
BUCKET_NAME = "pbs-project-ai-data-dev-v1" # 테라폼으로 만든 버킷 이름
REGION = "ap-northeast-2"

# S3 클라이언트 생성
s3 = boto3.client('s3', region_name=REGION)

def upload_sample_docs():
    source_dir = "./sample_docs"
    
    if not os.path.exists(source_dir):
        print(f"Error: {source_dir} 폴더를 찾을 수 없습니다.")
        return

    for filename in os.listdir(source_dir):
        file_path = os.path.join(source_dir, filename)
        if os.path.isfile(file_path):
            print(f"Uploading {filename} to S3...")
            s3.upload_file(file_path, BUCKET_NAME, filename)
            print(f"Successfully uploaded {filename}")

if __name__ == "__main__":
    upload_sample_docs()