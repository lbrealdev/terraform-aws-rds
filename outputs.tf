output "rds_parameter_group_names" {
  description = "Map of parameter group names created by rds_settings module"
  value       = { for k, v in module.rds_settings : k => v.parameter_group_name }
}

output "rds_parameter_group_arns" {
  description = "Map of parameter group ARNs created by rds_settings module"
  value       = { for k, v in module.rds_settings : k => v.parameter_group_arn }
}

output "rds_option_group_names" {
  description = "Map of option group names created by rds_settings module (for db_instance.option_group_name)"
  value       = { for k, v in module.rds_settings : k => v.option_group_name }
}

output "rds_option_group_ids" {
  description = "Map of option group IDs created by rds_settings module"
  value       = { for k, v in module.rds_settings : k => v.option_group_id }
}

output "rds_settings_map" {
  description = "Map of settings with their corresponding parameter and option group names"
  value = {
    for k, settings in local.rds_settings : k => {
      parameter_group_name = module.rds_settings[k].parameter_group_name
      option_group_name    = module.rds_settings[k].option_group_name
      family               = settings.parameter_group.family
      engine_name          = settings.option_group.engine_name
      major_engine_version = settings.option_group.major_engine_version
    }
  }
}

output "db_subnet_group_name" {
  description = "Name of the DB subnet group used by RDS instances"
  value       = module.rds_networking_data.db_subnet_group_name
}

output "db_subnet_group_subnets" {
  description = "List of subnet IDs in the DB subnet group"
  value       = module.rds_networking_data.db_subnet_group_subnets
}

output "security_group_ids" {
  description = "List of security group IDs associated with the RDS instances"
  value       = module.rds_networking_data.security_group_ids
}

output "security_group_names" {
  description = "List of security group names associated with the RDS instances"
  value       = module.rds_networking_data.security_group_names
}

output "security_groups_by_name" {
  description = "Map of security group names to their IDs"
  value       = module.rds_networking_data.security_groups_by_name
}
