variable "enabled" {
  description = "Enable or disable the rollback module"
  type        = bool
  default     = false
}

variable "snapshot_identifier" {
  description = "The identifier of the DB snapshot to restore from"
  type        = string
  default     = null
}

variable "stop_source_instance" {
  description = "Whether to stop the source instance after rollback is created"
  type        = bool
  default     = false
}

variable "source_instance_id" {
  description = "ID of the source instance to stop (the failed upgrade)"
  type        = string
  default     = null
}

# All the same variables as rds_instance module
variable "identifier" {
  description = "The name of the RDS instance"
  type        = string
}

variable "engine" {
  description = "The database engine to use (e.g., mysql, postgres, sqlserver-web) - not required when using snapshot_identifier"
  type        = string
  default     = null
}

variable "engine_version" {
  description = "The engine version to use - not required when using snapshot_identifier"
  type        = string
  default     = null
}

variable "instance_class" {
  description = "The instance type of the RDS instance"
  type        = string
}

variable "username" {
  description = "Username for the master DB user"
  type        = string
  default     = null
}

variable "password" {
  description = "Password for the master DB user"
  type        = string
  sensitive   = true
  default     = null
}

variable "allocated_storage" {
  description = "The allocated storage in gigabytes - not required when using snapshot_identifier (inherited from snapshot)"
  type        = number
  default     = null
}

variable "storage_type" {
  description = "Storage type - not required when using snapshot_identifier (inherited from snapshot)"
  type        = string
  default     = null
}

variable "skip_final_snapshot" {
  description = "Determines whether a final DB snapshot is created before the DB instance is deleted"
  type        = bool
  default     = true
}

variable "final_snapshot_identifier" {
  description = "The name of your final DB snapshot when this DB instance is deleted. Must be provided if skip_final_snapshot is false"
  type        = string
  default     = null
}

variable "option_group_name" {
  description = "Name of the DB option group to associate"
  type        = string
  default     = null
}

variable "parameter_group_name" {
  description = "Name of the DB parameter group to associate"
  type        = string
  default     = null
}

variable "db_subnet_group_name" {
  description = "Name of DB subnet group"
  type        = string
  default     = null
}

variable "allow_major_version_upgrade" {
  description = "Indicates that major version upgrades are allowed"
  type        = bool
  default     = null
}

variable "auto_minor_version_upgrade" {
  description = "Indicates that minor engine upgrades will be applied automatically during the maintenance window"
  type        = bool
  default     = null
}

variable "apply_immediately" {
  description = "Specifies whether any database modifications are applied immediately"
  type        = bool
  default     = null
}

variable "vpc_security_group_ids" {
  description = "List of VPC security groups to associate"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
