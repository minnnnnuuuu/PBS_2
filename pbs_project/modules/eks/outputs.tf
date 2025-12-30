# modules/eks/outputs.tf

output "cluster_name" {
  description = "EKS Cluster Name"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS Control Plane API Endpoint"
  value       = aws_eks_cluster.this.endpoint
}

output "node_security_group_id" {
  description = "Security Group ID attached to EKS nodes"
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

# ★ [요구사항 3] ARN 정보 공유용 ★
output "cluster_role_arn" {
  description = "IAM Role ARN for EKS Cluster"
  value       = aws_iam_role.cluster.arn
}

output "node_role_arn" {
  description = "IAM Role ARN for EKS Nodes"
  value       = aws_iam_role.node.arn
}

# [추가] LBC 설치할 때 필요한 OIDC 정보
output "oidc_provider_arn" {
  description = "IAM OIDC Provider ARN"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "IAM OIDC Provider URL (trimmed)"
  value       = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

output "lbc_role_arn" {
  description = "IAM Role ARN for AWS Load Balancer Controller"
  value       = aws_iam_role.lbc_role.arn
}
output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}