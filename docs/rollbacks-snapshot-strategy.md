# RDS Snapshot Rollback Strategy

This document describes the snapshot-based rollback approach for RDS major version upgrades.

## Overview

The snapshot rollback strategy provides a simple, cost-effective way to revert to a previous database version when upgrade issues occur. This approach trades zero-downtime capability for simplicity and cost savings.

## Architecture flow

```
SNAPSHOT ROLLBACK FLOW

BEFORE UPGRADE
v15.xx (Active) -> Create snapshot (Daily/Monthly backup) -> Upgrade to v16.xx (Issues)

ROLLBACK
Stop v16.xx (Preserve for debugging) -> Restore v15.xx from snapshot -> New endpoint/ARN

⚠️ DATA LOSS
Changes after the snapshot timestamp are lost.
```

## Terraform implementation

### Module structure

```
modules/
├── rds_snapshot_rollback/    # NEW: Rollback management module
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
```

### Usage example

(Keep using the same example as your original `ROLLBACK_STRATEGY.md`; move it here verbatim if you prefer.)

## Best practices

- Always snapshot before major upgrades.
- Test restore procedure in a non-prod environment.
- Document rollback decision criteria (rollback vs fix-forward).
- Keep snapshots for at least ~7 days.
- Tag snapshots clearly.
- Monitor storage costs and delete old snapshots after successful upgrades.
- Communicate planned maintenance/rollback windows.

## References

- AWS RDS Snapshots: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_CreateSnapshot.html
- AWS Restore from Snapshot: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_RestoreFromSnapshot.html
- Terraform `aws_db_snapshot`:
  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_snapshot
- Terraform restore-from-snapshot:
  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance#restoring-from-a-snapshot
