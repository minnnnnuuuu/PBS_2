# 파일: PBS_2/bootstrap/main.tf

provider "aws" {
  region = "ap-northeast-2"
}
# =================================================================
# 1. Terraform State 관리용 (S3 + DynamoDB)
# =================================================================
# 1. 상태 저장용 S3 (장부 보관함)
resource "aws_s3_bucket" "tfstate" {
  bucket = "pbs-project-tfstate-soldesk-pbs"  # 아까 정한 그 이름
  
  force_destroy = true # 장부파일 있어도 삭제
  lifecycle {
    prevent_destroy = false # 파괴허용 but 나중에 true로 교체
  }
}
# 1-2. S3 버저닝 활성화 (실수했을 때 되돌리기 위해)
resource "aws_s3_bucket_versioning" "tfstate_versioning" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 1-3. 잠금장치 DynamoDB (동시 수정 방지)
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
# =================================================================
# 2. DNS 관리용 (Route53 Hosted Zone) - 시연 안정성 핵심!
# =================================================================

# 2-1. 도메인 그릇(Zone) 생성
# 주의: apply 후 나오는 네임서버를 HostingKR에 등록해야 함!
resource "aws_route53_zone" "main" {
  name    = "soldesk-group4-pbs-project.click"  # ★ [수정필요] 구매하신 실제 도메인(예: cloudreaminu.cloud)으로 꼭 바꾸세요!
  comment = "Bootstrap: Managed manually for Demo Stability"
}

# =================================================================
# 3. 결과 출력 (Outputs)
# =================================================================

output "nameservers" {
  description = "HostingKR(도메인 구입처)에 등록할 네임서버 목록 4개"
  value       = aws_route53_zone.main.name_servers
}

output "zone_id" {
  description = "Route53 Zone ID (나중에 루트 main.tf가 참고할 값)"
  value       = aws_route53_zone.main.zone_id
}

output "s3_bucket_name" {
  description = "생성된 S3 버킷 이름"
  value       = aws_s3_bucket.tfstate.bucket
}