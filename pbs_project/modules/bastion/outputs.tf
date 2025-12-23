output "instance_id" {
  description = "베스천 인스턴스 ID (접속할 때 필요)"
  value       = aws_instance.bastion.id
}

output "public_ip" {
  description = "베스천 공인 IP"
  value       = aws_instance.bastion.public_ip
}