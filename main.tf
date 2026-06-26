terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "location" {
  description = "Azure region for the resources"
  type        = string
  default     = "centralus"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-bff-webapp-centralus"
}

variable "storage_account_prefix" {
  description = "Prefix for the storage account name"
  type        = string
  default     = "bffappst"
}

variable "app_name" {
  description = "Base name for the web app"
  type        = string
  default     = "bff-webapp"
}

variable "app_service_plan_name" {
  description = "Name of the App Service plan"
  type        = string
  default     = "plan-bff-webapp-centralus"
}

variable "sql_admin_login" {
  description = "Administrator login for Azure SQL"
  type        = string
  default     = "sqladminuser"
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

resource "random_password" "sql_password" {
  length           = 20
  special          = true
  override_special = "!-_#"
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_storage_account" "sa" {
  name                            = substr(replace("${var.storage_account_prefix}${random_string.suffix.result}", "-", ""), 0, 24)
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
}

resource "azurerm_service_plan" "plan" {
  name                = var.app_service_plan_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = "Linux"
  sku_name            = "F1"
}

resource "azurerm_linux_web_app" "webapp" {
  name                = "${var.app_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  service_plan_id     = azurerm_service_plan.plan.id
  https_only          = true

  site_config {
    always_on = false

    application_stack {
      dotnet_version = "8.0"
    }
  }

  app_settings = {
    ASPNETCORE_ENVIRONMENT = "Production"
    ConnectionStrings__Default = "Server=tcp:${azurerm_mssql_server.sql.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.db.name};Persist Security Info=False;User ID=${var.sql_admin_login};Password=${random_password.sql_password.result};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_mssql_server" "sql" {
  name                         = "sql-${var.app_name}-${random_string.suffix.result}"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_login
  administrator_login_password = random_password.sql_password.result
  minimum_tls_version          = "1.2"
}

resource "azurerm_mssql_database" "db" {
  name      = "sqldb-${var.app_name}"
  server_id = azurerm_mssql_server.sql.id
  sku_name  = "Basic"
}

resource "azurerm_mssql_firewall_rule" "azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.sql.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "storage_account_name" {
  value = azurerm_storage_account.sa.name
}

output "storage_account_primary_endpoint" {
  value = azurerm_storage_account.sa.primary_blob_endpoint
}

output "web_app_name" {
  value = azurerm_linux_web_app.webapp.name
}

output "web_app_url" {
  value = "https://${azurerm_linux_web_app.webapp.default_hostname}"
}

output "sql_server_fqdn" {
  value = azurerm_mssql_server.sql.fully_qualified_domain_name
}

output "sql_database_name" {
  value = azurerm_mssql_database.db.name
}
