variable "prefix" {
  description = "Prefix for resource naming"
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
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
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

variable "option_group_options" {
  description = "List of options for the option group"
  type = list(object({
    option_name                   = string
    db_security_group_memberships = optional(list(string), [])
    option_settings = optional(list(object({
      name  = string
      value = string
    })), [])
    port                           = optional(number)
    version                        = optional(string)
    vpc_security_group_memberships = optional(list(string), [])
  }))
  default = []
}
