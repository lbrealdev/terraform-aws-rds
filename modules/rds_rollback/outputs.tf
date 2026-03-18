output "endpoint" {
  description = "The connection endpoint for the RDS instance"
  value       = var.enabled ? module.rds_instance[0].endpoint : null
}

output "address" {
  description = "The hostname of the RDS instance"
  value       = var.enabled ? module.rds_instance[0].address : null
}

output "port" {
  description = "The port on which the database accepts connections"
  value       = var.enabled ? module.rds_instance[0].port : null
}

output "arn" {
  description = "The ARN of the RDS instance"
  value       = var.enabled ? module.rds_instance[0].arn : null
}

output "id" {
  description = "The RDS instance ID"
  value       = var.enabled ? module.rds_instance[0].id : null
}

output "resource_id" {
  description = "The RDS Resource ID"
  value       = var.enabled ? module.rds_instance[0].resource_id : null
}

output "status" {
  description = "The RDS instance status"
  value       = var.enabled ? module.rds_instance[0].status : null
}

output "availability_zone" {
  description = "The availability zone of the RDS instance"
  value       = var.enabled ? module.rds_instance[0].availability_zone : null
}

output "engine" {
  description = "The database engine"
  value       = var.enabled ? module.rds_instance[0].engine : null
}

output "engine_version" {
  description = "The running version of the database"
  value       = var.enabled ? module.rds_instance[0].engine_version : null
}
