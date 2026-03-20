locals {
  rds_parameters = []
  rds_options    = []

  rds_settings = {

    "v15" = {
      name = ""

      parameter_group = {
        family      = "sqlserver-web-15.0"
        description = "Production parameter group for SQL 19"
        parameters  = local.rds_parameters
      }

      option_group = {
        engine_name          = "sqlserver-web"
        major_engine_version = "15.00"
        description          = "RDS Option Group - SQL 19 (v15)"
        options              = local.rds_options
      }
    }

    "v16" = {
      name = ""

      parameter_group = {
        family      = "sqlserver-web-16.0"
        description = "Production parameter group for SQL 22"
        parameters  = local.rds_parameters
      }

      option_group = {
        engine_name          = "sqlserver-web"
        major_engine_version = "16.00"
        description          = "RDS Option Group - SQL 22 (v16)"
        options              = local.rds_options
      }
    }

    # Example with custom name
    # "v17" = {
    #   name = "infra"
    #
    #   parameter_group = {
    #     family      = "sqlserver-web-16.0"
    #     description = "Infra adjustment parameter group"
    #     parameters  = local.rds_parameters
    #   }
    #
    #   option_group = {
    #     engine_name          = "sqlserver-web"
    #     major_engine_version = "16.00"
    #     description          = "Infra adjustment option group"
    #     options              = local.rds_options
    #   }
    # }
  }
}
