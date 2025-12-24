# pbs_project/modules/security_group/output.tf
output "bastion_sg_id" {
  value = aws_security_group.bastion.id
}

output "rds_sg_id" {
  value = aws_security_group.rds.id
}