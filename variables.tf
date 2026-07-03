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
variable "networking_enabled" {
  description = "Enable or disable the networking data lookups"
  type        = bool
  default     = true
}

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

variable "rds_settings_tags" {
  description = "Tags to add to the RDS settings resources (parameter and option groups)"
  type        = map(string)
  default     = {}
}

# RDS Instance - Instance
variable "db_instance_enabled" {
  description = "Enable or disable the RDS instance creation"
  type        = bool
  default     = true
}

variable "db_instance_class" {
  description = "The instance type of the RDS instance"
  type        = string
  default     = "db.t3.medium"
}

# RDS Instance - Engine
variable "db_engine" {
  description = "Database engine for the root stack: sqlserver-web or mariadb"
  type        = string
  default     = "sqlserver-web"

  validation {
    condition     = contains(["sqlserver-web", "mariadb"], var.db_engine)
    error_message = "db_engine must be sqlserver-web or mariadb."
  }
}

variable "rds_settings_active_key" {
  description = "Stable key in local.rds_settings for the running instance (e.g. v15, v10_11). Defaults by db_engine."
  type        = string
  default     = null
  nullable    = true
}

variable "rds_engine_version" {
  description = "The engine version for the RDS instance"
  type        = string
  default     = "15.00.4198.2.v1"
}

# RDS Instance - Maintenance
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

# RDS Instance - User
variable "db_username" {
  description = "Username for the master DB user"
  type        = string
}

variable "db_password" {
  description = "Password for the master DB user"
  type        = string
  sensitive   = true
}

# RDS Instance - Storage
variable "db_allocated_storage" {
  description = "The allocated storage in gigabytes for the RDS instance"
  type        = number
  default     = 100
}

variable "db_instance_storage_type" {
  description = "Type of storage for the RDS instance: 'standard' (magnetic), 'gp2' (general purpose SSD), 'gp3' (gp2 with better performance and pricing), or 'io1'/'io2' (provisioned IOPS SSD)"
  type        = string
  default     = "gp2"
}

variable "db_instance_storage_throughput" {
  description = "Throughput (mebibytes per second) for gp3 storage. Required when storage_type is 'gp3', value must be between 125 and 1000"
  type        = number
  default     = null
}

variable "db_instance_iops" {
  description = "Provisioned IOPS (I/O operations per second). Optional for gp3 (3000-16000), required for io1/io2 (1000-64000)"
  type        = number
  default     = null
}

variable "db_instance_max_allocated_storage" {
  description = "Maximum storage (in GiB) that Amazon RDS can automatically scale to. By default, Storage Autoscaling is disabled."
  type        = number
  default     = null
}

variable "db_instance_storage_encrypted" {
  description = "Specifies whether the DB instance is encrypted. The default is false if not specified."
  type        = bool
  default     = null
}

variable "db_instance_kms_key_id" {
  description = "The ARN of the KMS encryption key used to encrypt the DB instance. Required when storage_encrypted is true and a custom key is desired."
  type        = string
  default     = null
}

# RDS Instance - License
variable "license_model" {
  description = "License model for the DB instance (e.g., license-included, bring-your-own-license)"
  type        = string
  default     = null
}

# RDS Instance - Domain
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

variable "rollback_skip_final_snapshot" {
  description = "Skip final snapshot for rollback instance"
  type        = bool
  default     = false
}

variable "rollback_final_snapshot_identifier" {
  description = "The name of your final DB snapshot when rollback instance is deleted. Required if rollback_skip_final_snapshot is false"
  type        = string
  default     = null
}

variable "rollback_apply_immediately" {
  description = "Apply changes immediately for rollback instance"
  type        = bool
  default     = true
}
