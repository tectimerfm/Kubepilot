# Aqua Enforcer Helm (optional installation) - EKS

data "aws_eks_cluster" "this" {
  name       = aws_eks_cluster.eks.name
  depends_on = [aws_eks_cluster.eks]
}

data "aws_eks_cluster_auth" "this" {
  name       = aws_eks_cluster.eks.name
  depends_on = [aws_eks_cluster.eks]
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
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

  depends_on = [aws_eks_cluster.eks]
}
