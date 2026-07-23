locals {
  # Size suffix from db.<family>.<size> (e.g. medium from db.t3.medium).
  instance_class_parts  = split(".", var.instance_class)
  instance_class_size   = length(local.instance_class_parts) >= 3 ? local.instance_class_parts[2] : ""
  instance_class_family = length(local.instance_class_parts) >= 2 ? local.instance_class_parts[1] : ""

  # Rank of known AWS DB instance size suffixes (higher = larger).
  instance_size_rank = {
    micro      = 0
    small      = 1
    medium     = 2
    large      = 3
    xlarge     = 4
    "2xlarge"  = 5
    "3xlarge"  = 6
    "4xlarge"  = 7
    "6xlarge"  = 8
    "8xlarge"  = 9
    "9xlarge"  = 10
    "10xlarge" = 11
    "12xlarge" = 12
    "16xlarge" = 13
    "18xlarge" = 14
    "24xlarge" = 15
    "32xlarge" = 16
    "48xlarge" = 17
    "96xlarge" = 18
  }

  instance_size_rank_value = lookup(local.instance_size_rank, local.instance_class_size, -1)
  is_burstable_t_family    = can(regex("^t[0-9]+", local.instance_class_family))

  # Edition floors from AWS SQL Server instance class support (not the full orderable matrix).
  # EE: xlarge+ for all families. SE: t* must be xlarge+; other families large+.
  sqlserver_ee_class_ok = var.engine != "sqlserver-ee" || local.instance_size_rank_value >= local.instance_size_rank["xlarge"]
  sqlserver_se_class_ok = var.engine != "sqlserver-se" || (
    local.is_burstable_t_family
    ? local.instance_size_rank_value >= local.instance_size_rank["xlarge"]
    : local.instance_size_rank_value >= local.instance_size_rank["large"]
  )
  sqlserver_instance_class_ok = local.sqlserver_ee_class_ok && local.sqlserver_se_class_ok
}

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

  lifecycle {
    precondition {
      condition     = local.sqlserver_instance_class_ok
      error_message = "Invalid combination: engine=${var.engine} with instance_class=${var.instance_class}. SQL Server Enterprise requires size xlarge or larger; Standard requires xlarge+ for burstable (db.t*) classes and large+ otherwise. See https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/SQLServer.Concepts.General.InstanceClasses.html"
    }
  }
}
