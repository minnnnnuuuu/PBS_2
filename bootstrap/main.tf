# 파일: PBS_2/bootstrap/main.tf

provider "aws" {
  region = "ap-northeast-2"
}

# 1. 상태 저장용 S3 (이름은 유니크하게!)
resource "aws_s3_bucket" "tfstate" {
  bucket = "pbs-project-tfstate-soldesk-pbs"  # 아까 정한 그 이름
  
  force_destroy = true # 장부파일 있어도 삭제
  lifecycle {
    prevent_destroy = false # 파괴허용 but 나중에 true로 교체
  }
}

resource "aws_s3_bucket_versioning" "tfstate_versioning" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 2. 잠금장치 DynamoDB
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}