variable "name" {}
variable "vpc_id" {}
variable "subnet_id" {}
variable "iam_instance_profile" {}

# 1. 최신 아마존 리눅스 2023 이미지 찾기 (자동)
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# 2. Bastion 전용 보안그룹 (나가는 건 자유, 들어오는 건 SSM이라 포트 안 열어도 됨!)
resource "aws_security_group" "bastion_sg" {
  name        = "${var.name}-bastion-sg"
  description = "Security group for Bastion Host"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-bastion-sg" }
}

# 3. EC2 인스턴스 생성
resource "aws_instance" "bastion" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"  # 프리티어 가능, 저렴함
  subnet_id     = var.subnet_id

  iam_instance_profile   = var.iam_instance_profile # 아까 만든 신분증 착용
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  associate_public_ip_address = true

  tags = { Name = "${var.name}-bastion" }
}
