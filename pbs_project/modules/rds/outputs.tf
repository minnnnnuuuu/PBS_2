output "endpoint" {
  description = "DB 접속 주소 (쓰기 전용)"
  value       = aws_rds_cluster.main.endpoint
}

output "reader_endpoint" {
  description = "DB 읽기 전용 주소"
  value       = aws_rds_cluster.main.reader_endpoint
}

output "rds_endpoint" {
  description = "RDS 클러스터/인스턴스 엔드포인트"
  # 실제 리소스 이름에 따라 아래 주석 중 하나를 선택하거나 이름을 맞추세요
  value = aws_rds_cluster.main.endpoint # 만약 클러스터(Aurora 등)라면
  # value = aws_db_instance.this.endpoint # 만약 단일 DB 인스턴스라면
}