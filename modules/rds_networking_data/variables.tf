variable "enabled" {
  description = "Enable or disable the data lookups"
  type        = bool
  default     = true
}

variable "db_subnet_group_name" {
  description = "Name of the existing DB subnet group to fetch"
  type        = string
  default     = null
}

variable "security_group_names" {
  description = "List of existing security group names to fetch"
  type        = list(string)
  default     = []
}

variable "vpc_id" {
  description = "VPC ID where security groups are located (required if fetching security groups by name)"
  type        = string
  default     = null
}
