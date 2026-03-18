variable "identifier" {
  description = "The name of the RDS instance"
  type        = string
}

variable "engine" {
  description = "The database engine to use (e.g., mysql, postgres)"
  type        = string
}

variable "engine_version" {
  description = "The engine version to use"
  type        = string
}

variable "instance_class" {
  description = "The instance type of the RDS instance"
  type        = string
}

variable "username" {
  description = "Username for the master DB user"
  type        = string
}

variable "password" {
  description = "Password for the master DB user"
  type        = string
  sensitive   = true
}

variable "allocated_storage" {
  description = "The allocated storage in gigabytes"
  type        = number
  default     = 20
}

variable "storage_type" {
  description = "One of 'standard' (magnetic), 'gp2' (general purpose SSD), or 'io1' (provisioned IOPS SSD)"
  type        = string
  default     = "gp2"
}

variable "skip_final_snapshot" {
  description = "Determines whether a final DB snapshot is created before the DB instance is deleted"
  type        = bool
  default     = true
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
