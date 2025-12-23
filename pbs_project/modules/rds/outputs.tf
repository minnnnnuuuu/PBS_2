output "endpoint" {
  description = "DB 접속 주소 (쓰기 전용)"
  value       = aws_rds_cluster.main.endpoint
}

output "reader_endpoint" {
  description = "DB 읽기 전용 주소"
  value       = aws_rds_cluster.main.reader_endpoint
}