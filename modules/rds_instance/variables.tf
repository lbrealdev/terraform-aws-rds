variable "identifier" {
  description = "The name of the RDS instance"
  type        = string
}

variable "enabled" {
  description = "Enable or disable the RDS instance creation"
  type        = bool
}

variable "engine" {
  description = "The database engine to use (e.g., mariadb, mysql, postgres, sqlserver-web). For SQL Server Enterprise (sqlserver-ee) and Standard (sqlserver-se), instance_class must meet AWS edition minimum sizes."
  type        = string
}

variable "engine_version" {
  description = "The engine version to use"
  type        = string
}

variable "instance_class" {
  description = "The instance type of the RDS instance. SQL Server Enterprise requires xlarge or larger (e.g. db.t3.xlarge); Standard requires xlarge+ for burstable (db.t*) classes and large+ otherwise. Web/Express allow smaller classes such as db.t3.medium."
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
  description = "The allocated storage in gigabytes (minimum 20 for SQL Server Express, 100 for SQL Server Web/Standard)"
  type        = number
}

variable "storage_type" {
  description = "Storage type: standard (magnetic), gp2 (general purpose SSD), gp3 (gp2 with better performance and pricing), io1/io2 (provisioned IOPS SSD)"
  type        = string
  default     = "gp2"

  validation {
    condition     = can(regex("^(standard|gp2|gp3|io1|io2)$", var.storage_type))
    error_message = "storage_type must be one of: standard, gp2, gp3, io1, io2"
  }
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

variable "snapshot_identifier" {
  description = "The identifier of the DB snapshot to restore from"
  type        = string
  default     = null
}

variable "license_model" {
  description = "License model for the DB instance"
  type        = string
  default     = null
}

# SQL Server Domain Integration (Windows Authentication via AWS Directory Service)

variable "domain" {
  description = "The Active Directory domain (DNS name) for SQL Server Windows Authentication via AWS Directory Service. Only supported for sqlserver-ee engine."
  type        = string
  default     = null
}

variable "domain_iam_role_name" {
  description = "The name of the IAM role that RDS uses to join the Active Directory domain. Required when domain is specified."
  type        = string
  default     = null
}

variable "storage_throughput" {
  description = "Throughput (mebibytes per second) for gp3 storage. Required when storage_type is 'gp3', value must be between 125 and 1000"
  type        = number
  default     = null

  validation {
    condition     = var.storage_throughput == null || (var.storage_type == "gp3" && var.storage_throughput >= 125 && var.storage_throughput <= 1000)
    error_message = "storage_throughput for gp3 must be between 125 and 1000. Set to null if not using gp3."
  }
}

variable "iops" {
  description = "Provisioned IOPS (I/O operations per second). Optional for gp3 (3000-16000), required for io1/io2 (1000-64000)"
  type        = number
  default     = null

  validation {
    condition = var.iops == null || (
      (var.storage_type == "gp3" && var.iops >= 3000 && var.iops <= 16000) ||
      (contains(["io1", "io2"], var.storage_type) && var.iops >= 1000 && var.iops <= 64000)
    )
    error_message = "iops must be between 3,000-16,000 for gp3, or 1,000-64,000 for io1/io2. Set to null if not using optional IOPS."
  }
}

variable "max_allocated_storage" {
  description = "Maximum storage (in GiB) that Amazon RDS can automatically scale to. By default, Storage Autoscaling is disabled. Set to a value greater than or equal to allocated_storage to enable it."
  type        = number
  default     = null
}

variable "storage_encrypted" {
  description = "Specifies whether the DB instance is encrypted. The default is false if not specified."
  type        = bool
  default     = null
}

variable "kms_key_id" {
  description = "The ARN of the KMS encryption key used to encrypt the DB instance. Required when storage_encrypted is true and a custom key is desired."
  type        = string
  default     = null
}
