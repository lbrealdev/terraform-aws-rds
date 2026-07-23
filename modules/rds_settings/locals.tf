locals {
  # Suffix from major_engine_version: first segment before "." (e.g. 15.00 → 15, 10.11 → 10, 11.4 → 11).
  major_version        = split(".", var.major_engine_version)[0]
  effective_name       = coalesce(var.name, var.prefix)
  parameter_group_name = "${local.effective_name}-parameter-group-${local.major_version}"
  option_group_name    = "${local.effective_name}-option-group-${local.major_version}"
}
