provider "azurerm" {
  features {}

  # If empty, AzureRM will use your current az CLI subscription context
  subscription_id = var.azure_subscription_id != "" ? var.azure_subscription_id : null
}
