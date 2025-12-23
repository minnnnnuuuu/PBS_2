# 파일 위치: pbs_project/modules/kms/main.tf

variable "name" {
  description = "프로젝트 이름"
  type        = string
}

resource "aws_kms_key" "main" {
  description             = "Master Key for ${var.name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "${var.name}-master-key"
  }
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.name}-key"
  target_key_id = aws_kms_key.main.key_id
}