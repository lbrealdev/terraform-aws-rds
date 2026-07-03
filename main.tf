provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      resource   = "rds"
      deployment = "terraform"
    }
  }
}

module "rds_networking_data" {
  source = "./modules/rds_networking_data"

  enabled              = var.networking_enabled
  vpc_id               = var.vpc_id
  db_subnet_group_name = var.db_subnet_group_name
  security_group_names = var.security_group_names
}

module "rds_settings" {
  source = "./modules/rds_settings"

  for_each = local.rds_settings

  name                        = try(each.value.name, "")
  prefix                      = var.prefix_name
  family                      = each.value.parameter_group.family
  parameter_group_description = try(each.value.parameter_group.description, null)
  parameter_group_parameters  = try(each.value.parameter_group.parameters, [])

  engine_name              = each.value.option_group.engine_name
  major_engine_version     = each.value.option_group.major_engine_version
  option_group_description = each.value.option_group.description
  option_group_options     = try(each.value.option_group.options, [])
  tags                     = var.rds_settings_tags
}

module "rds_instance" {
  source = "./modules/rds_instance"

  # --- Instance ---
  enabled        = var.db_instance_enabled
  identifier     = format("rds-%s-db-instance-test", var.prefix_name)
  instance_class = var.db_instance_class

  # --- Engine ---
  engine         = module.rds_settings[local.rds_settings_active_key].engine_name
  engine_version = var.db_engine_version

  # --- Settings ---
  option_group_name    = module.rds_settings[local.rds_settings_active_key].option_group_name
  parameter_group_name = module.rds_settings[local.rds_settings_active_key].parameter_group_name

  # --- Network ---
  db_subnet_group_name   = module.rds_networking_data.db_subnet_group_name
  vpc_security_group_ids = module.rds_networking_data.security_group_ids

  # --- Maintenance ---
  apply_immediately           = var.db_apply_immediately
  allow_major_version_upgrade = var.db_allow_major_version_upgrade
  auto_minor_version_upgrade  = var.db_auto_minor_version_upgrade
  skip_final_snapshot         = var.db_skip_final_snapshot

  # --- User ---
  username = var.db_username
  password = var.db_password

  # --- Storage ---
  allocated_storage     = var.db_allocated_storage
  storage_type          = var.db_instance_storage_type
  storage_throughput    = var.db_instance_storage_throughput
  iops                  = var.db_instance_iops
  max_allocated_storage = var.db_instance_max_allocated_storage
  storage_encrypted     = var.db_instance_storage_encrypted
  kms_key_id            = var.db_instance_kms_key_id

  # --- License ---
  license_model = var.license_model

  # --- Domain ---
  domain               = var.domain
  domain_iam_role_name = var.domain_iam_role_name
}

module "rds_rollback" {
  source = "./modules/rds_rollback"

  enabled             = var.rollback_enabled
  snapshot_identifier = var.rollback_snapshot_identifier

  stop_source_instance = var.rollback_stop_source_instance
  source_instance_id   = try(module.rds_instance.id, null)

  # Same configuration as original instance
  identifier     = var.rollback_identifier
  instance_class = var.rollback_instance_class

  db_subnet_group_name   = module.rds_networking_data.db_subnet_group_name
  vpc_security_group_ids = module.rds_networking_data.security_group_ids

  parameter_group_name = module.rds_settings[local.rds_settings_active_key].parameter_group_name
  option_group_name    = module.rds_settings[local.rds_settings_active_key].option_group_name

  skip_final_snapshot       = var.rollback_skip_final_snapshot
  final_snapshot_identifier = var.rollback_final_snapshot_identifier
  apply_immediately         = var.rollback_apply_immediately

  tags = {
    Purpose = "rollback"
  }
}

check "rds_settings_active_key_valid" {
  assert {
    condition     = contains(keys(local.rds_settings), local.rds_settings_active_key)
    error_message = "rds_settings_active_key \"${local.rds_settings_active_key}\" is not defined in local.rds_settings."
  }
}
