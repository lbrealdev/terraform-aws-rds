provider "aws" {
  region = "eu-central-1"
  default_tags {
    tags = {
      resource   = "rds"
      managed-by = "terraform"
    }
  }
}

module "rds_networking_data" {
  source = "./modules/rds_networking_data"

  enabled              = true
  vpc_id               = "vpc-12345678"
  db_subnet_group_name = "my-existing-db-subnet-group"
  security_group_names = ["rds-security-group", "app-security-group"]
}

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

module "rds_instance" {
  source = "./modules/rds_instance"

  identifier     = format("rds-%s-db-instance-test", local.prefix_name)
  instance_class = "db.t3.medium"

  engine         = module.rds_settings["v15"].engine_name
  engine_version = local.rds_engine_version

  option_group_name      = module.rds_settings["v15"].option_group_name
  parameter_group_name   = module.rds_settings["v15"].parameter_group_name
  db_subnet_group_name   = module.rds_networking_data.db_subnet_group_name
  vpc_security_group_ids = module.rds_networking_data.security_group_ids

  apply_immediately           = true
  allow_major_version_upgrade = true
  auto_minor_version_upgrade  = true

  password = "testnet"
  username = "testnet54321"
}
