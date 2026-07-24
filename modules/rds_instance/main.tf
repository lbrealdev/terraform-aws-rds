resource "aws_db_instance" "rds" {
  count = var.enabled ? 1 : 0

  identifier                  = var.identifier
  engine                      = var.engine
  engine_version              = var.engine_version
  instance_class              = var.instance_class
  username                    = var.username
  password                    = var.password
  allocated_storage           = var.allocated_storage
  storage_type                = var.storage_type
  storage_throughput          = var.storage_throughput
  iops                        = var.iops
  max_allocated_storage       = var.max_allocated_storage
  storage_encrypted           = var.storage_encrypted
  kms_key_id                  = var.kms_key_id
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
  license_model               = var.license_model
  domain                      = var.domain
  domain_iam_role_name        = var.domain_iam_role_name
  multi_az                    = var.multi_az

  lifecycle {
    precondition {
      condition     = local.sqlserver_instance_class_ok
      error_message = "Invalid combination: engine=${var.engine} with instance_class=${var.instance_class}. SQL Server Enterprise requires size xlarge or larger; Standard requires xlarge+ for burstable (db.t*) classes and large+ otherwise. See https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/SQLServer.Concepts.General.InstanceClasses.html"
    }
  }
}
