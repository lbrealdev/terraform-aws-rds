output "endpoint" {
  description = "The connection endpoint for the RDS instance"
  value       = aws_db_instance.rds.endpoint
}

output "arn" {
  description = "The ARN of the RDS instance"
  value       = aws_db_instance.rds.arn
}

output "id" {
  description = "The RDS instance ID"
  value       = aws_db_instance.rds.id
}

output "resource_id" {
  description = "The RDS Resource ID"
  value       = aws_db_instance.rds.resource_id
}

output "status" {
  description = "The RDS instance status"
  value       = aws_db_instance.rds.status
}

output "address" {
  description = "The hostname of the RDS instance"
  value       = aws_db_instance.rds.address
}

output "port" {
  description = "The port on which the database accepts connections"
  value       = aws_db_instance.rds.port
}

output "availability_zone" {
  description = "The availability zone of the RDS instance"
  value       = aws_db_instance.rds.availability_zone
}

output "engine" {
  description = "The database engine"
  value       = aws_db_instance.rds.engine
}

output "engine_version" {
  description = "The running version of the database"
  value       = aws_db_instance.rds.engine_version
}
