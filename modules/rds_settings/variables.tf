variable "prefix_name" {
  description = "Prefix name to be used for resource naming"
  type        = string
}

variable "family" {
  description = "The family of the DB parameter group"
  type        = string
  default     = ""
}

variable "parameter_group_description" {
  description = "Description for the DB parameter group"
  type        = string
  default     = ""
}

variable "parameter_group_parameters" {
  description = "List of parameters for the parameter group"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "engine_name" {
  description = "Name of the database engine for the option group"
  type        = string
  default     = ""
}

variable "major_engine_version" {
  description = "Major version of the database engine for the option group"
  type        = string
  default     = ""
}

variable "option_group_description" {
  description = "Description for the DB option group"
  type        = string
  default     = ""
}
