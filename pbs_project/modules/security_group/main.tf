# pbs_project/modules/security_group/main.tf
variable "vpc_id" {} #vpc_id라는 값을 밖에서 받을 거라는 의미
variable "name" {}

# 1. Bastion Host용 보안 그룹 (S5 Section)
# - 외부에서 관리자(SSH)가 들어올 수 있게 허용
resource "aws_security_group" "bastion" {
  # name        = "${var.name}-bastion-sg"
  name_prefix = "${var.name}-bastion-sg-"
  description = "Security group for Bastion Host"
  vpc_id      = var.vpc_id

  # 인바운드: SSH (22번 포트) 허용
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 보안상 본인 IP로 제한하는 게 좋지만, 실습용이라 전체 허용
  }

  # 아웃바운드: 모든 곳으로 나가는 것 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.name}-bastion-sg" }
}

# 2. RDS(데이터베이스)용 보안 그룹 (S6 Section)
# - VPC 내부(EKS, Bastion)에서만 DB 접속 허용
resource "aws_security_group" "rds" {
  # name        = "${var.name}-rds-sg"
  name_prefix        = "${var.name}-rds-sg-"
  description = "Security group for RDS"
  vpc_id      = var.vpc_id

  # 인바운드: PostgreSQL (5432번 포트) 허용
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/18"] # VPC 내부에서만 접속 가능 (10.0.0.0/18)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  lifecycle{
    create_before_destroy = true
  }

  tags = { Name = "${var.name}-rds-sg" }
}