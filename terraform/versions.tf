terraform {
  required_version = "~> 1.16"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.3"
    }

    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }

    http = {
      source  = "hashicorp/http"
      version = "~> 3.6"
    }
  }
}
