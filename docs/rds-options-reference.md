# AWS RDS Parameter Groups and Option Groups Reference

This document provides references for AWS RDS parameter group families and option group engines.

## Parameter group families

Use these tables to pick the correct `family`, `engine_name`, and `major_engine_version` for `locals.tf` / `rds_settings`.

### SQL Server

| Edition | Family | Engine | Major version |
|---------|--------|--------|---------------|
| Web | `sqlserver-web-15.0` | `sqlserver-web` | `15.00` |
| Standard | `sqlserver-se-15.0` | `sqlserver-se` | `15.00` |
| Standard | `sqlserver-se-16.0` | `sqlserver-se` | `16.00` |
| Enterprise | `sqlserver-ee-15.0` | `sqlserver-ee` | `15.00` |
| Enterprise | `sqlserver-ee-16.0` | `sqlserver-ee` | `16.00` |
| Express | `sqlserver-ex-15.0` | `sqlserver-ex` | `15.00` |

### MySQL

| Family | Engine | Major version |
|--------|--------|---------------|
| `mysql5.6` | `mysql` | `5.6` |
| `mysql5.7` | `mysql` | `5.7` |
| `mysql8.0` | `mysql` | `8.0` |

### MariaDB

| Family | Engine | Major version |
|--------|--------|---------------|
| `mariadb10.6` | `mariadb` | `10.6` |
| `mariadb10.11` | `mariadb` | `10.11` |
| `mariadb11.4` | `mariadb` | `11.4` |

### PostgreSQL

| Family | Engine | Major version |
|--------|--------|---------------|
| `postgres10` | `postgres` | `10` |
| `postgres11` | `postgres` | `11` |
| `postgres12` | `postgres` | `12` |
| `postgres13` | `postgres` | `13` |
| `postgres14` | `postgres` | `14` |
| `postgres15` | `postgres` | `15` |
| `postgres16` | `postgres` | `16` |

### Aurora MySQL

| Family | Engine | Major version |
|--------|--------|---------------|
| `aurora-mysql5.7` | `aurora-mysql` | `5.7` |
| `aurora-mysql8.0` | `aurora-mysql` | `8.0` |

### Aurora PostgreSQL

| Family | Engine | Major version |
|--------|--------|---------------|
| `aurora-postgresql10` | `aurora-postgresql` | `10` |
| `aurora-postgresql11` | `aurora-postgresql` | `11` |
| `aurora-postgresql12` | `aurora-postgresql` | `12` |
| `aurora-postgresql13` | `aurora-postgresql` | `13` |
| `aurora-postgresql14` | `aurora-postgresql` | `14` |
| `aurora-postgresql15` | `aurora-postgresql` | `15` |
| `aurora-postgresql16` | `aurora-postgresql` | `16` |

### Selecting the right parameter group family

Each row in the tables above maps to three fields in this stack:

| Field | Where it goes | Example (MariaDB 10.11) |
|-------|---------------|-------------------------|
| `family` | `parameter_group.family` in `locals.tf` | `mariadb10.11` |
| `engine_name` | `option_group.engine_name` in `locals.tf` | `mariadb` |
| `major_engine_version` | `option_group.major_engine_version` in `locals.tf` | `10.11` |

**Checklist**

1. **Match the engine** — `family`, `engine_name`, and `major_engine_version` must belong to the same engine (see tables above).
2. **Match the edition** — for SQL Server, pick the row for your edition (Web, Standard, Enterprise, Express).
3. **Match the target version** — the family must align with the major version you plan to run or upgrade to.
4. **Aurora vs RDS** — Aurora families (`aurora-*`) are not interchangeable with non-Aurora families.
5. **Use stable keys in `locals.tf`** — keep version keys (e.g. `v15`, `v10`, `v11`) stable across upgrades so Terraform does not recreate groups unnecessarily.

**In this repo**

- Define parameter/option groups in `local.rds_settings` in `locals.tf` using a row from the tables above (`family`, `engine_name`, `major_engine_version`).
- Set `rds_settings_active_key` in `.tfvars` to the stable key for the running instance (e.g. `v15`, `v10`).
- Set `db_engine_version` in `.tfvars` to the full AWS engine version string.
- Document your choices in PRs or runbooks so rollback and audits stay traceable.

## Option groups

Option groups are separate from parameter groups. Not every engine uses them — this section documents engines that have been validated in this project. Others can be added over time as they are tested.

### SQL Server

#### `SQLSERVER_BACKUP_RESTORE`

Enables native backup and restore to Amazon S3 using AWS credentials.

| Setting | Required | Description |
|---------|----------|-------------|
| `IAM_ROLE_ARN` | Yes | ARN of the IAM role with S3 permissions |

#### `SQLSERVER_BACKUP`

Configures automatic backup schedules for SQL Server.

| Setting | Required | Default | Description |
|---------|----------|---------|-------------|
| `BACKUP_HOUR` | No | `2` | Hour of day (0–23) |
| `BACKUP_MINUTE` | No | `0` | Minute (0–59) |
| `ENABLED` | No | — | Enable automatic backups (`true` or `false`) |

### MariaDB

Option groups use `engine_name = "mariadb"` with a matching `major_engine_version` from the parameter group table (e.g. `10.11`, `11.4`).

#### `MARIADB_AUDIT_PLUGIN`

Enables the MariaDB audit plugin (MariaDB 10.3+).

## Verifying engine versions (AWS CLI)

Use `aws rds describe-db-engine-versions` to confirm `EngineVersion`, `DBParameterGroupFamily`, and option-group `MajorEngineVersion` before updating `locals.tf` or `db_engine_version` in `.tfvars`. Requires AWS credentials and a configured region.

```bash
# MariaDB — list versions and parameter group families in the current region
aws rds describe-db-engine-versions \
  --engine mariadb \
  --query 'DBEngineVersions[].{Version:EngineVersion,Family:DBParameterGroupFamily,Major:MajorEngineVersion}' \
  --output table

# MariaDB — inspect a major line (e.g. 10.11 for locals key v10)
aws rds describe-db-engine-versions \
  --engine mariadb \
  --engine-version 10.11 \
  --query 'DBEngineVersions[0].{Version:EngineVersion,Family:DBParameterGroupFamily,Major:MajorEngineVersion}' \
  --output table

# SQL Server Web — list available full version strings
aws rds describe-db-engine-versions \
  --engine sqlserver-web \
  --query 'DBEngineVersions[].{Version:EngineVersion,Family:DBParameterGroupFamily,Major:MajorEngineVersion}' \
  --output table
```

Map CLI output to this stack: `Family` → `parameter_group.family`, `Major` → `option_group.major_engine_version`, `Version` → `db_engine_version` in `.tfvars`.

## References

- Amazon RDS Parameter Groups: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_ParamGroups.html
- Amazon RDS Option Groups: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Resources.html#CHAP_Options
