locals {
  major_version        = split(".", var.major_engine_version)[0]
  effective_name       = coalesce(var.name, var.prefix)
  parameter_group_name = "${local.effective_name}-parameter-group-${local.major_version}"
  option_group_name    = "${local.effective_name}-option-group-${local.major_version}"
}

resource "aws_db_option_group" "option_group" {
  name                     = local.option_group_name
  engine_name              = var.engine_name
  major_engine_version     = var.major_engine_version
  option_group_description = var.option_group_description
  tags                     = var.tags

  dynamic "option" {
    for_each = var.option_group_options
    content {
      option_name                    = option.value.option_name
      db_security_group_memberships  = option.value.db_security_group_memberships
      port                           = option.value.port
      version                        = option.value.version
      vpc_security_group_memberships = option.value.vpc_security_group_memberships

      dynamic "option_settings" {
        for_each = option.value.option_settings
        content {
          name  = option_settings.value.name
          value = option_settings.value.value
        }
      }
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_parameter_group" "parameter_group" {
  name        = local.parameter_group_name
  family      = var.family
  description = var.parameter_group_description != "" ? var.parameter_group_description : "Parameter group for ${local.effective_name}"
  tags        = var.tags

  dynamic "parameter" {
    for_each = var.parameter_group_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}
