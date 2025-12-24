# =========================================================================
# 1. Variables (입력받을 재료 - 루트 main.tf와 이름 맞춤)
# =========================================================================

# [수정] name 대신 project_name과 environment를 받습니다.
variable "project_name" {
  description = "프로젝트 이름"
  type        = string
}

variable "environment" {
  description = "환경 이름 (dev, prod 등)"
  type        = string
}

variable "vpc_id" {
  description = "EFS가 생성될 VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "EFS 마운트 타겟을 생성할 서브넷 ID 목록"
  type        = list(string)
}

variable "node_security_group_ids" {
  description = "NFS 접근을 허용할 EKS 노드 보안 그룹 ID 목록"
  type        = list(string)
}

variable "kms_key_arn" {
  description = "데이터 암호화에 사용할 KMS Key ARN"
  type        = string
}

# =========================================================================
# 2. Resources (리소스 생성)
# =========================================================================

# (1) EFS 파일 시스템 본체
resource "aws_efs_file_system" "this" {
  # [수정] 두 변수를 합쳐서 이름을 만듭니다.
  creation_token   = "${var.project_name}-${var.environment}-efs"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  encrypted        = true
  kms_key_id       = var.kms_key_arn

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-efs"
    Environment = var.environment
  }
}

# (2) EFS 전용 보안 그룹
resource "aws_security_group" "efs_sg" {
  name        = "${var.project_name}-${var.environment}-efs-sg"
  description = "Allow NFS traffic from EKS nodes"
  vpc_id      = var.vpc_id

  ingress {
    description     = "NFS from EKS Nodes"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = var.node_security_group_ids
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-efs-sg"
  }
}

# (3) 마운트 타겟
resource "aws_efs_mount_target" "this" {
  count           = length(var.subnet_ids)
  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = var.subnet_ids[count.index]
  security_groups = [aws_security_group.efs_sg.id]
}