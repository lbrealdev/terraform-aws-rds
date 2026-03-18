output "db_subnet_group_name" {
  description = "Name of the fetched DB subnet group"
  value       = var.enabled && var.db_subnet_group_name != null ? data.aws_db_subnet_group.subnet_group[0].name : null
}

output "db_subnet_group_arn" {
  description = "ARN of the fetched DB subnet group"
  value       = var.enabled && var.db_subnet_group_name != null ? data.aws_db_subnet_group.subnet_group[0].arn : null
}

output "db_subnet_group_description" {
  description = "Description of the fetched DB subnet group"
  value       = var.enabled && var.db_subnet_group_name != null ? data.aws_db_subnet_group.subnet_group[0].description : null
}

output "db_subnet_group_subnets" {
  description = "List of subnet IDs in the DB subnet group"
  value       = var.enabled && var.db_subnet_group_name != null ? data.aws_db_subnet_group.subnet_group[0].subnet_ids : []
}

output "security_group_ids" {
  description = "List of IDs of the fetched security groups"
  value       = var.enabled ? [for sg in data.aws_security_group.security_groups : sg.id] : []
}

output "security_group_names" {
  description = "List of names of the fetched security groups"
  value       = var.enabled ? [for sg in data.aws_security_group.security_groups : sg.name] : []
}

output "security_groups_by_name" {
  description = "Map of security group names to their IDs"
  value       = var.enabled ? { for name, sg in data.aws_security_group.security_groups : name => sg.id } : {}
}

output "enabled" {
  description = "Whether the module is enabled"
  value       = var.enabled
}
