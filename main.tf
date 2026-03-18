module "rds_settings" {
  source = "./modules/rds_settings"

  for_each = local.rds_settings

  prefix_name                 = local.prefix_name
  family                      = each.value.parameter_group.family
  parameter_group_description = try(each.value.parameter_group.description, null)
  parameter_group_parameters  = try(each.value.parameter_group.parameters, [])

  engine_name              = each.value.option_group.engine_name
  major_engine_version     = each.value.option_group.major_engine_version
  option_group_description = each.value.option_group.description
}

# module "rds_instance" {
#   source = "./modules/rds_instance"
#
#   identifier     = ""
#   instance_class = "db.t3.medium"
#
#   engine         = module.rds_settings["v15"].engine_name
#   engine_version = local.rds_engine_version
#
#   option_group_name    = module.rds_settings["v15"].option_group_name
#   parameter_group_name = module.rds_settings["v15"].parameter_group_name
#   db_subnet_group_name = data.aws_db_subnet_group.subnet_group.name
#
#   apply_immediately           = true
#   allow_major_version_upgrade = true
#   auto_minor_version_upgrade  = true
#
#   password = "testnet"
#   username = "testnet54321"
# }
