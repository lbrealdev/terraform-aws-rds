# AWS RDS Parameter Groups and Option Groups Reference

This document provides comprehensive references for AWS RDS parameter group families and option group engines.

## SQL Server Parameter Group Families

### SQL Server Web Edition
| Family | Engine | Version | Compatible With |
|--------|--------|---------|-----------------|
| `sqlserver-web-15.0` | sqlserver-web | 15.00 | Web applications requiring lower licensing cost |

### SQL Server Standard Edition
| Family | Engine | Version | Compatible With |
|--------|--------|---------|-----------------|
| `sqlserver-se-15.0` | sqlserver-se | 15.00 | Standard business applications |
| `sqlserver-se-16.0` | sqlserver-se | 16.00 | Standard business applications with SQL Server 2019+ |

### SQL Server Enterprise Edition
| Family | Engine | Version | Compatible With |
|--------|--------|---------|-----------------|
| `sqlserver-ee-15.0` | sqlserver-ee | 15.00 | Enterprise applications with advanced features |
| `sqlserver-ee-16.0` | sqlserver-ee | 16.00 | Enterprise applications with SQL Server 2019+ |

### SQL Server Express Edition
| Family | Engine | Version | Compatible With |
|--------|--------|---------|-----------------|
| `sqlserver-ex-15.0` | sqlserver-ex | 15.00 | Small applications, dev/test, non-critical workloads |

## MySQL Parameter Group Families

| Family | Engine | Version | Compatible With |
|--------|--------|---------|-----------------|
| `mysql5.6` | mysql | 5.6 | Legacy MySQL 5.6 applications |
| `mysql5.7` | mysql | 5.7 | MySQL 5.7 applications |
| `mysql8.0` | mysql | 8.0 | Modern MySQL 8.0 applications |

## PostgreSQL Parameter Group Families

| Family | Engine | Version | Compatible With |
|--------|--------|---------|-----------------|
| `postgres10` | postgres | 10.18 | PostgreSQL 10.x |
| `postgres11` | postgres | 11.x | PostgreSQL 11.x |
| `postgres12` | postgres | 12.x | PostgreSQL 12.x |
| `postgres13` | postgres | 13.x | PostgreSQL 13.x |
| `postgres14` | postgres | 14.x | PostgreSQL 14.x |
| `postgres15` | postgres | 15.x | PostgreSQL 15.x |
| `postgres16` | postgres | 16.x | PostgreSQL 16.x |

## Aurora MySQL Parameter Group Families

| Family | Engine | Version | Compatible With |
|--------|--------|---------|-----------------|
| `aurora-mysql5.7` | aurora-mysql | 5.7 | Aurora MySQL 5.7 |
| `aurora-mysql8.0` | aurora-mysql | 8.0 | Aurora MySQL 8.0 |

## Aurora PostgreSQL Parameter Group Families

| Family | Engine | Version | Compatible With |
|--------|--------|---------|-----------------|
| `aurora-postgresql10` | aurora-postgresql | 10 | Aurora PostgreSQL 10.x |
| `aurora-postgresql11` | aurora-postgresql | 11 | Aurora PostgreSQL 11.x |
| `aurora-postgresql12` | aurora-postgresql | 12 | Aurora PostgreSQL 12.x |
| `aurora-postgresql13` | aurora-postgresql | 13 | Aurora PostgreSQL 13.x |
| `aurora-postgresql14` | aurora-postgresql | 14 | Aurora PostgreSQL 14.x |
| `aurora-postgresql15` | aurora-postgresql | 15 | Aurora PostgreSQL 15.x |
| `aurora-postgresql16` | aurora-postgresql | 16 | Aurora PostgreSQL 16.x |

## SQL Server Option Groups

| Option Group Name | Engine | Description | Common Options |
|-------------------|--------|-------------|----------------|
| `default-sqlserver-web-15.0` | sqlserver-web | Default option group for SQL Server Web 15.0 | Backup/Restore, SQL Native Backup |
| `default-sqlserver-se-15.0` | sqlserver-se | Default option group for SQL Server Standard 15.0 | Backup/Restore, SQL Native Backup |
| `default-sqlserver-ee-15.0` | sqlserver-ee | Default option group for SQL Server Enterprise 15.0 | Backup/Restore, SQL Native Backup |
| `default-sqlserver-web-16.0` | sqlserver-web | Default option group for SQL Server Web 16.0 | Backup/Restore, SQL Native Backup |
| `default-sqlserver-se-16.0` | sqlserver-se | Default option group for SQL Server Standard 16.0 | Backup/Restore, SQL Native Backup |
| `default-sqlserver-ee-16.0` | sqlserver-ee | Default option group for SQL Server Enterprise 16.0 | Backup/Restore, SQL Native Backup |

### SQL Server Option Types

#### SQLSERVER_BACKUP_RESTORE
Enables native backup and restore to Amazon S3 using AWS credentials.

**Required Option Settings:**
- `IAM_ROLE_ARN`: ARN of the IAM role with S3 permissions

#### SQLSERVER_BACKUP
Configures automatic backup schedules for SQL Server.

**Optional Option Settings:**
- `BACKUP_HOUR`: Hour (0-23) for backup (default: 2)
- `BACKUP_MINUTE`: Minute (0-59) for backup (default: 0)
- `ENABLED`: Enable automatic backup (`true` or `false`)

## Selecting the Right Parameter Group Family

### Considerations:

1. **Engine Edition**: Choose based on your license (Web, Standard, Enterprise, Express)
2. **Engine Version**: Must match your SQL Server/MySQL/PostgreSQL version
3. **Aurora Compatibility**: Use Aurora-specific families for Aurora databases
4. **Performance**: Some families have optimized settings for specific workloads

### Best Practices:

- Use matching family and engine for consistent parameter defaults
- For SQL Server, align parameter group family with your actual installed edition
- Consider using custom parameter groups for production environments
- Document parameter group choices for rollback and auditing

## Command Reference

### List Available DB Engine Versions

```bash
aws rds describe-db-engine-versions \
  --engine <engine_name> \
  --query 'DBEngineVersions[*].[Engine,EngineVersion,DBParameterGroupFamily,SupportedTimeZones]'
```

### List Available Parameter Group Families

```bash
aws rds describe-db-parameter-groups \
  --query 'DBParameterGroups[*].[DBParameterGroupName,DBParameterGroupFamily]'
```

### List Available Option Groups

```bash
aws rds describe-option-groups \
  --engine <engine_name> \
  --query 'OptionGroups[*].[OptionGroupName,EngineName,EngineVersion]'
```

## Migration Guide

### SQL Server Web to Standard Upgrade

1. Create new parameter group: `sqlserver-se-16.0`
2. Create new option group: `default-sqlserver-se-16.0`
3. Update terraform configuration with new families
4. Deploy new instance
5. Migrate data
6. Switch applications to new instance
7. Remove old instance after validation

### Multi-Version Deployment

For blue/green deployments with multiple SQL Server versions:

```hcl
module "rds_settings_v15" {
  source = "./modules/rds_settings"
  for_each = {
    "v15" = { major_engine_version = "15.00", family = "sqlserver-se-15.0" }
  }
  engine_name = "sqlserver-se"
  major_engine_version = each.value.major_engine_version
  family = each.value.family
}

module "rds_settings_v16" {
  source = "./modules/rds_settings"
  for_each = {
    "v16" = { major_engine_version = "16.00", family = "sqlserver-se-16.0" }
  }
  engine_name = "sqlserver-se"
  major_engine_version = each.value.major_engine_version
  family = each.value.family
}
```

## Troubleshooting

### Parameter Group Mismatch Error

**Error**: `Invalid DB parameter group family`

**Solution**: Ensure `family` matches your `engine_name` and `major_engine_version`.

### Option Group Compatibility Error

**Error**: `Option group is not compatible with the specified DB instance`

**Solution**: Use option group with matching engine and version.

### Aurora Version Compatibility

**Error**: `Aurora MySQL version is not supported in this region`

**Solution**: Check region-specific Aurora support at: https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/SupportedAuroraMySQLClasses.html

## References

- [Amazon RDS Parameter Groups](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_ParamGroups.html)
- [Amazon RDS Option Groups](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Resources.html#CHAP_Options)
- [Supported Engine Versions](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_SupportedProducts.html)