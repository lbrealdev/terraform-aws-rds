# AWS Configuration
aws_region  = "eu-central-1"
prefix_name = "dev"

# Networking
vpc_id               = "vpc-12345678"
db_subnet_group_name = "my-existing-db-subnet-group"
security_group_names = ["rds-security-group", "app-security-group"]

# RDS Instance Configuration
db_instance_class              = "db.t3.medium"
db_username                    = "testnet"
db_password                    = "testnet54321"
db_apply_immediately           = true
db_allow_major_version_upgrade = true
db_auto_minor_version_upgrade  = true
db_skip_final_snapshot         = false

# Rollback Configuration (Set rollback_enabled = true to trigger rollback)
rollback_enabled              = false
rollback_snapshot_identifier  = ""
rollback_stop_source_instance = true
rollback_identifier           = "mydb-rollback"
rollback_instance_class       = "db.t3.medium"
rollback_engine_version       = "15.00.4198.2.v1"
rollback_skip_final_snapshot  = false
rollback_apply_immediately    = true
