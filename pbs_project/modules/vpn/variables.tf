# modules/vpn/variables.tf

variable "vpc_id" {
  description = "VPN을 연결할 AWS VPC의 ID"
  type        = string
}

variable "school_public_ip" {
  description = "학교(온프레미스) 라우터의 외부 공인 IP"
  type        = string
}

variable "school_cidr" {
  description = "학교(온프레미스) 내부 네트워크 대역 (CIDR)"
  type        = string
}

variable "private_route_table_ids" {
  description = "VPN 경로를 전파할 VPC의 프라이빗 라우팅 테이블 ID 목록"
  type        = list(string)
}

variable "tags" {
  description = "리소스에 붙일 태그"
  type        = map(string)
  default     = {}
}