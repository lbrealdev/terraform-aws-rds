# Fetch existing DB Subnet Group
data "aws_db_subnet_group" "subnet_group" {
  count = var.enabled && var.db_subnet_group_name != null ? 1 : 0
  name  = var.db_subnet_group_name
}

# Fetch existing Security Groups by name
data "aws_security_group" "security_groups" {
  for_each = var.enabled && length(var.security_group_names) > 0 ? toset(var.security_group_names) : []

  name   = each.value
  vpc_id = var.vpc_id
}
