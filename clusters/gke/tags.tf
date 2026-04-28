locals {
  # GCP labels must be lowercase and match [a-z0-9_-]
  common_labels = {
    owner     = "support"
    purpose   = "gke-repro"
    workspace = terraform.workspace
  }

  kubernetes_version_label = (
    var.kubernetes_version != null && var.kubernetes_version != ""
    ? regexreplace(lower(var.kubernetes_version), "[^0-9a-z_-]", "_")
    : null
  )

  containerd_version_label = (
    var.containerd_version != null && var.containerd_version != ""
    ? regexreplace(lower(var.containerd_version), "[^0-9a-z_-]", "_")
    : null
  )

  gke_resource_labels = merge(
    local.common_labels,
    local.kubernetes_version_label != null ? { kubernetes_version = local.kubernetes_version_label } : {},
    local.containerd_version_label != null ? { containerd_version = local.containerd_version_label } : {}
  )
}
