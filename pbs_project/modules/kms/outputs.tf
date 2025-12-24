# 파일 위치: pbs_project/modules/kms/outputs.tf

output "key_id" {
  value = aws_kms_key.main.key_id
}
# 출력값 이름이 반드시 'key_arn' 이어야 합니다.
output "key_arn" {
  value = aws_kms_key.main.arn 
  # (주의: aws_kms_key.main 부분은 님 KMS 코드의 리소스 이름에 맞춰주세요!)
}