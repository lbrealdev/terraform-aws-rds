module "rds_instance" {
  source = "../rds_instance"

  count = var.enabled ? 1 : 0

  enabled = var.enabled

  # Pass through all variables to rds_instance
  identifier                  = var.identifier
  engine                      = var.engine
  engine_version              = var.engine_version
  instance_class              = var.instance_class
  username                    = var.username
  password                    = var.password
  allocated_storage           = var.allocated_storage
  storage_type                = var.storage_type
  skip_final_snapshot         = var.skip_final_snapshot
  final_snapshot_identifier   = var.final_snapshot_identifier
  option_group_name           = var.option_group_name
  parameter_group_name        = var.parameter_group_name
  db_subnet_group_name        = var.db_subnet_group_name
  allow_major_version_upgrade = var.allow_major_version_upgrade
  auto_minor_version_upgrade  = var.auto_minor_version_upgrade
  apply_immediately           = var.apply_immediately
  vpc_security_group_ids      = var.vpc_security_group_ids
  tags                        = var.tags
  snapshot_identifier         = var.snapshot_identifier
}

# Stop the source instance after rollback is created
resource "aws_rds_instance_state" "stop_source" {
  count = var.enabled && var.stop_source_instance ? 1 : 0

  identifier = var.source_instance_id
  state      = "stopped"

  # Ensures this runs AFTER rollback instance is ready
  depends_on = [module.rds_instance]
}
