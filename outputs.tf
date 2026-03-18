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
