# 생성된 EFS의 ID (K8s StorageClass 설정 시 필요)
output "id" {
  description = "The ID of the EFS file system, 생성된 EFS 파일 시스템 ID"
  value       = aws_efs_file_system.this.id
}

# 생성된 EFS의 DNS 주소 (직접 마운트 시 필요)
output "dns_name" {
  description = "The DNS name of the EFS file system"
  value       = aws_efs_file_system.this.dns_name
}
