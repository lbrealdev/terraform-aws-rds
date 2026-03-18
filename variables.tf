variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-central-1"
}

variable "prefix_name" {
  description = "Prefix for all resource names"
  type        = string
  default     = "dev"
}

# Networking Configuration
variable "vpc_id" {
  description = "VPC ID where networking resources are located"
  type        = string
}

variable "db_subnet_group_name" {
  description = "Name of the existing DB subnet group"
  type        = string
}

variable "security_group_names" {
  description = "List of security group names to attach to RDS"
  type        = list(string)
}

# RDS Instance Configuration
variable "db_instance_class" {
  description = "The instance type of the RDS instance"
  type        = string
  default     = "db.t3.medium"
}

variable "db_username" {
  description = "Username for the master DB user"
  type        = string
}

variable "db_password" {
  description = "Password for the master DB user"
  type        = string
  sensitive   = true
}

variable "db_apply_immediately" {
  description = "Specifies whether any database modifications are applied immediately"
  type        = bool
  default     = true
}

variable "db_allow_major_version_upgrade" {
  description = "Indicates that major version upgrades are allowed"
  type        = bool
  default     = true
}

variable "db_auto_minor_version_upgrade" {
  description = "Indicates that minor engine upgrades will be applied automatically"
  type        = bool
  default     = true
}

variable "db_skip_final_snapshot" {
  description = "Determines whether a final DB snapshot is created before deletion"
  type        = bool
  default     = false
}

# Rollback Configuration
variable "rollback_enabled" {
  description = "Enable or disable the rollback module"
  type        = bool
  default     = false
}

variable "rollback_snapshot_identifier" {
  description = "The identifier of the DB snapshot to restore from for rollback"
  type        = string
  default     = ""
}

variable "rollback_stop_source_instance" {
  description = "Automatically stop the source instance after rollback is created"
  type        = bool
  default     = true
}

variable "rollback_identifier" {
  description = "The identifier for the rollback RDS instance"
  type        = string
  default     = "mydb-rollback"
}

variable "rollback_instance_class" {
  description = "The instance type for the rollback RDS instance"
  type        = string
  default     = "db.t3.medium"
}

variable "rollback_engine_version" {
  description = "The engine version for the rollback RDS instance"
  type        = string
  default     = "15.00.4198.2.v1"
}

variable "rollback_skip_final_snapshot" {
  description = "Skip final snapshot for rollback instance"
  type        = bool
  default     = false
}

variable "rollback_apply_immediately" {
  description = "Apply changes immediately for rollback instance"
  type        = bool
  default     = true
}
