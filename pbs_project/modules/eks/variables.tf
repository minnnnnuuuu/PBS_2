# modules/eks/variables.tf

variable "project_name" { type = string }
variable "environment"  { type = string }
variable "vpc_id"        { type = string }
variable "subnet_ids"    { type = list(string) }

# ==========0104추가=========
variable "node_role_arn" {
  description = "IAM Role ARN for EKS Node Group"
  type        = string
}
# =====================

variable "waf_acl_arn" {
  description = "WAF ARN passed from root module"
  type        = string
}