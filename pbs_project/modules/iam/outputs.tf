# modules/iam/outputs.tf


output "instance_profile_name" {
  value = aws_iam_instance_profile.bastion_profile.name
}

output "eks_node_role_arn" {
  value = aws_iam_role.eks_node_role.arn
}