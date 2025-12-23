# 파일 위치: pbs_project/modules/kms/outputs.tf

output "key_id" {
  value = aws_kms_key.main.key_id
}