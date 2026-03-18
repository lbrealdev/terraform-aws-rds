locals {
  major_version_clean  = split(".", var.major_engine_version)[0]
  parameter_group_name = "${var.prefix_name}-parameter-group-v${local.major_version_clean}"
  option_group_name    = "${var.prefix_name}-option-group-v${local.major_version_clean}"
}

resource "aws_db_option_group" "option_group" {
  name                     = local.option_group_name
  engine_name              = var.engine_name
  major_engine_version     = var.major_engine_version
  option_group_description = var.option_group_description

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_parameter_group" "parameter_group" {
  name        = local.parameter_group_name
  family      = var.family
  description = var.parameter_group_description != "" ? var.parameter_group_description : "Parameter group for ${var.prefix_name}"

  dynamic "parameter" {
    for_each = var.parameter_group_parameters
    content {
      name  = parameter.value.name
      value = parameter.value.value
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}
