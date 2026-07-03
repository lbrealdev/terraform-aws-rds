# AWS RDS Parameter Groups and Option Groups Reference

This document provides references for AWS RDS parameter group families and option group engines.

## SQL Server parameter group families

| Edition | Family | Engine | Major version |
|---------|--------|--------|---------------|
| Web | `sqlserver-web-15.0` | `sqlserver-web` | `15.00` |
| Standard | `sqlserver-se-15.0` | `sqlserver-se` | `15.00` |
| Standard | `sqlserver-se-16.0` | `sqlserver-se` | `16.00` |
| Enterprise | `sqlserver-ee-15.0` | `sqlserver-ee` | `15.00` |
| Enterprise | `sqlserver-ee-16.0` | `sqlserver-ee` | `16.00` |
| Express | `sqlserver-ex-15.0` | `sqlserver-ex` | `15.00` |

## MySQL parameter group families

- `mysql5.6` → engine: `mysql`, version: `5.6`
- `mysql5.7` → engine: `mysql`, version: `5.7`
- `mysql8.0` → engine: `mysql`, version: `8.0`

## MariaDB parameter group families

- `mariadb10.6` → engine: `mariadb`, version: `10.6`
- `mariadb10.11` → engine: `mariadb`, version: `10.11`
- `mariadb11.4` → engine: `mariadb`, version: `11.4`

## MariaDB option groups

MariaDB option groups use `engine_name = "mariadb"` with a matching `major_engine_version` (e.g. `10.11`, `11.4`).

### Option group types

#### `MARIADB_AUDIT_PLUGIN`

Enables the MariaDB audit plugin (MariaDB 10.3+).

## PostgreSQL parameter group families

- `postgres10` → engine: `postgres`, version: `10`
- `postgres11` → engine: `postgres`, version: `11`
- `postgres12` → engine: `postgres`, version: `12`
- `postgres13` → engine: `postgres`, version: `13`
- `postgres14` → engine: `postgres`, version: `14`
- `postgres15` → engine: `postgres`, version: `15`
- `postgres16` → engine: `postgres`, version: `16`

## Aurora MySQL parameter group families

- `aurora-mysql5.7` → engine: `aurora-mysql`, version: `5.7`
- `aurora-mysql8.0` → engine: `aurora-mysql`, version: `8.0`

## Aurora PostgreSQL parameter group families

- `aurora-postgresql10` → engine: `aurora-postgresql`, version: `10`
- `aurora-postgresql11` → engine: `aurora-postgresql`, version: `11`
- `aurora-postgresql12` → engine: `aurora-postgresql`, version: `12`
- `aurora-postgresql13` → engine: `aurora-postgresql`, version: `13`
- `aurora-postgresql14` → engine: `aurora-postgresql`, version: `14`
- `aurora-postgresql15` → engine: `aurora-postgresql`, version: `15`
- `aurora-postgresql16` → engine: `aurora-postgresql`, version: `16`

## SQL Server option groups

### Option group types

#### `SQLSERVER_BACKUP_RESTORE`

Enables native backup and restore to Amazon S3 using AWS credentials.

**Required option settings**
- `IAM_ROLE_ARN`: ARN of the IAM role with S3 permissions

#### `SQLSERVER_BACKUP`

Configures automatic backup schedules for SQL Server.

**Optional option settings**
- `BACKUP_HOUR`: hour (0-23), default `2`
- `BACKUP_MINUTE`: minute (0-59), default `0`
- `ENABLED`: enable automatic backups (`true` or `false`)

## Selecting the right parameter group family

**Considerations**
1. Engine edition (web/se/ee/ex)
2. Engine version compatibility
3. Aurora vs non-Aurora compatibility
4. Performance/workload fit

**Best practices**
- Use matching `family` + `engine_name` + `major_engine_version`
- Document parameter/option group choices for rollback/auditing

## References

- Amazon RDS Parameter Groups: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_ParamGroups.html
- Amazon RDS Option Groups: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Resources.html#CHAP_Options
