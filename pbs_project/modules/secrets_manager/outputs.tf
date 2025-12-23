output "secret_arn" {
  description = "생성된 시크릿의 ARN"
  value       = aws_secretsmanager_secret.db_secret.arn
}