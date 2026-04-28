locals {
  common_tags = {
    Owner     = "support"
    Purpose   = "aks-repro"
    Workspace = terraform.workspace
    ContainerdVersion = var.containerd_version != null ? var.containerd_version : ""
  }
}
