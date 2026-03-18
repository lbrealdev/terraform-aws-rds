locals {
  rds_engine_version = "15.00.4198.2.v1"

  rds_settings = {

    "v15" = {
      # parameter group v15
      parameter_group = {
        family      = "sqlserver-web-15.0"
        description = "Production parameter group for SQL 19"
        parameters  = []
      }

      # option group
      option_group = {
        engine_name          = "sqlserver-web"
        major_engine_version = "15.00"
        description          = "RDS Option Group - SQL 19 (v15)"
      }
    }

    "v16" = {
      # parameter group v16
      parameter_group = {
        family      = "sqlserver-web-16.0"
        description = "Production parameter group for SQL 22"
        parameters  = []
      }

      # option group
      option_group = {
        engine_name          = "sqlserver-web"
        major_engine_version = "16.00"
        description          = "RDS Option Group - SQL 22 (v16)"
      }
    }
  }
}
