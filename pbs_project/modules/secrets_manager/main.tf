variable "name" {
  description = "프로젝트 이름"
  type        = string
}

variable "kms_key_id" {
  description = "비밀번호를 암호화할 KMS 키 ID"
  type        = string
}

# 랜덤 꼬리표 생성
resource "random_id" "suffix" {
  byte_length = 4  # 4바이트 길이의 랜덤 값 (예: a1b2c3d4) 생성
}

# 랜덤 비밀번호 생성 (16자리, 특수문자 포함)
resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?" # DB가 싫어하는 문자는 뺌
}

# 금고 껍데기 생성 (KMS 키로 잠금)
resource "aws_secretsmanager_secret" "db_secret" {
  name        = "${var.name}/db/master-password-${random_id.suffix.hex}"
  description = "Master password for Aurora RDS"
  kms_key_id  = var.kms_key_id
  
  # 삭제 시 즉시 삭제되지 않고 7일간 복구 가능 기간 둠 (실수 방지) -> 개발 시 편의, 비용 절감을 위해 0으로 설정해둠
  recovery_window_in_days = 0
}

# 금고 안에 내용물(비밀번호) 넣기
resource "aws_secretsmanager_secret_version" "db_secret_val" {
  secret_id     = aws_secretsmanager_secret.db_secret.id
  secret_string = jsonencode({
    username = "adminuser"
    password = random_password.db_password.result
  })
}