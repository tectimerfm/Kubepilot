# Aqua Enforcer Helm (optional installation) - AKS

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes = {
    host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
  }
}

locals {
  aqua_set = var.install_aqua_enforcer ? concat(
    [
      { name = "global.platform",               value = var.aqua_platform },
      { name = "global.imageCredentials.create", value = "true" },
      { name = "serviceAccount.create",  value = "true" },
    ],
    var.aqua_enforcer_image_tag != null ? [{ name = "image.tag", value = var.aqua_enforcer_image_tag }] : [],
    var.gateway_address != null ? [{ name = "global.gateway.address", value = var.gateway_address }] : [],
    var.gateway_port != null ? [{ name = "global.gateway.port", value = tostring(var.gateway_port) }] : []
  ) : []

  aqua_set_sensitive = var.install_aqua_enforcer ? [
    { name = "global.imageCredentials.username", value = var.aqua_registry_username },
    { name = "global.imageCredentials.password", value = var.aqua_registry_password },
    { name = "enforcerToken",                    value = var.aqua_enforcer_token },
  ] : []
}

resource "helm_release" "aqua_enforcer" {
  count = var.install_aqua_enforcer ? 1 : 0

  name             = "aqua-enforcer"
  namespace        = "aqua"
  create_namespace = true

  repository = "https://helm.aquasec.com"
  chart      = "enforcer"

  set           = local.aqua_set
  set_sensitive = local.aqua_set_sensitive

  wait    = true
  timeout = 900

  lifecycle {
    precondition {
      condition = (
        !var.install_aqua_enforcer
        ||
        (
          var.aqua_platform          != null && var.aqua_platform          != "" &&
          var.aqua_registry_username != null && var.aqua_registry_username != "" &&
          var.aqua_registry_password != null && var.aqua_registry_password != "" &&
          var.aqua_enforcer_token    != null && var.aqua_enforcer_token    != ""
        )
      )
      error_message = "When install_aqua_enforcer=true you must set: aqua_platform, aqua_registry_username, aqua_registry_password, aqua_enforcer_token."
    }
  }

  depends_on = [azurerm_kubernetes_cluster.aks]
}
