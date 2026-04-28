locals {
  aks_os_sku = lookup(
    {
      ubuntu     = "Ubuntu"
      azurelinux = "AzureLinux"
      mariner    = "Mariner"
    },
    var.node_os,
    "Ubuntu"
  )

  # DNS prefix must be <= 54 chars
  dns_prefix = substr(local.name_prefix, 0, 54)
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${local.name_prefix}"
  location = var.azure_location
  tags     = local.common_tags
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-${local.name_prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = local.dns_prefix

  kubernetes_version = var.kubernetes_version

  default_node_pool {
    name       = "system"
    node_count = var.node_count
    vm_size    = var.vm_size
    os_sku     = local.aks_os_sku
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "aks_resource_group" {
  value = azurerm_resource_group.rg.name
}
