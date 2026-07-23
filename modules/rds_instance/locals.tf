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
