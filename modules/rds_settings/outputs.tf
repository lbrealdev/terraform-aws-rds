output "parameter_group_name" {
  description = "The name of the created parameter group"
  value       = aws_db_parameter_group.parameter_group.name
}

output "parameter_group_arn" {
  description = "The ARN of the created parameter group"
  value       = aws_db_parameter_group.parameter_group.arn
}

output "option_group_name" {
  description = "The name of the created option group"
  value       = aws_db_option_group.option_group.name
}

output "option_group_id" {
  description = "The ID of the created option group"
  value       = aws_db_option_group.option_group.id
}

output "engine_name" {
  description = "The engine name used for the RDS instance"
  value       = var.engine_name
}
