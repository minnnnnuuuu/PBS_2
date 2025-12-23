variable "name" {}
variable "vpc_id" {}
variable "subnets" { type = list(string) }  # DB가 들어갈 서브넷들
variable "sg_id" {}                         # DB 보안 그룹 ID
variable "secret_arn" {}                    # 비밀번호 금고 주소 (여기서 비번 가져옴)

# 1. 서브넷 그룹 (DB가 위치할 '금고 방' 묶음)
resource "aws_db_subnet_group" "main" {
  name       = "${var.name}-subnet-group"
  subnet_ids = var.subnets

  tags = { Name = "${var.name}-subnet-group" }
}

# 2. 비밀번호 금고에서 내용물(ID/PW) 몰래 읽어오기
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = var.secret_arn
}

# 3. Aurora 클러스터 (DB 컨트롤 타워)
resource "aws_rds_cluster" "main" {
  cluster_identifier      = "${var.name}-cluster"
  engine                  = "aurora-postgresql"
  engine_version          = "16.1"               # 안정적인 버전
  availability_zones      = ["ap-northeast-2a", "ap-northeast-2c"]
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [var.sg_id]
  
  # 핵심: 비밀번호를 코드에 안 적고 금고에서 가져옴!
  database_name           = "appdb"
  master_username         = jsondecode(data.aws_secretsmanager_secret_version.db_password.secret_string)["username"]
  master_password         = jsondecode(data.aws_secretsmanager_secret_version.db_password.secret_string)["password"]
  
  backup_retention_period = 7
  skip_final_snapshot     = true  # 실습용이라 삭제 시 스냅샷 생략
  
  tags = { Name = "${var.name}-cluster" }
}

# 4. Aurora 인스턴스 (실제 일하는 서버 2대)
resource "aws_rds_cluster_instance" "cluster_instances" {
  count              = 2 
  identifier         = "${var.name}-inst-${count.index}"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = "db.t3.medium"
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version
  
  tags = { Name = "${var.name}-inst-${count.index}" }
}