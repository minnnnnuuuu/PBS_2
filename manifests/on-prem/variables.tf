variable "cloudflare_token" {
  description = "Cloudflare Tunnel Token"
  type        = string
  sensitive   = true # 이 옵션을 주면 화면에 출력도 안 돼요!