locals {
  rds_parameters = []
  rds_options    = []

  rds_settings = {
    "v15" = {
      name = ""

      parameter_group = {
        family      = "sqlserver-web-15.0"
        description = "RDS Parameter Group for SQL Server 2019 (v15)"
        parameters  = local.rds_parameters
      }

      option_group = {
        engine_name          = "sqlserver-web"
        major_engine_version = "15.00"
        description          = "RDS Option Group for SQL Server 2019 Web (v15)"
        options              = local.rds_options
      }
    }

    "v16" = {
      name = ""

      parameter_group = {
        family      = "sqlserver-web-16.0"
        description = "RDS Parameter Group for SQL Server 2022 (v16)"
        parameters  = local.rds_parameters
      }

      option_group = {
        engine_name          = "sqlserver-web"
        major_engine_version = "16.00"
        description          = "RDS Option Group for SQL Server 2022 Web (v16)"
        options              = local.rds_options
      }
    }

    # Example with custom name
    "v17" = {
      name = "${var.prefix_name}-infra"

      parameter_group = {
        family      = "sqlserver-web-16.0"
        description = "RDS Parameter Group for SQL Server 2022 (v16)"
        parameters  = local.rds_parameters
      }

      option_group = {
        engine_name          = "sqlserver-web"
        major_engine_version = "16.00"
        description          = "Infra option group for SQL Server 2022 Web (v16)"
        options              = local.rds_options
      }
    }

    "v10" = {
      name = ""

      parameter_group = {
        family      = "mariadb10.11"
        description = "RDS Parameter Group for MariaDB 10.11"
        parameters  = local.rds_parameters
      }

      option_group = {
        engine_name          = "mariadb"
        major_engine_version = "10.11"
        description          = "RDS Option Group for MariaDB 10.11"
        options              = local.rds_options
      }
    }

    "v11" = {
      name = ""

      parameter_group = {
        family      = "mariadb11.4"
        description = "RDS Parameter Group for MariaDB 11.4"
        parameters  = local.rds_parameters
      }

      option_group = {
        engine_name          = "mariadb"
        major_engine_version = "11.4"
        description          = "RDS Option Group for MariaDB 11.4"
        options              = local.rds_options
      }
    }
  }

  rds_settings_active_key = var.rds_settings_active_key
}
