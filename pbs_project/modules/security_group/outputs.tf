output "bastion_sg_id" {
  value = aws_security_group.bastion.id
}

output "rds_sg_id" {
  value = aws_security_group.rds.id
}