# tags.tf

locals {
  common_tags = {
    Owner     = "support"
    Purpose   = "eks-repro"
    Workspace = terraform.workspace
    KubernetesVersion = var.kubernetes_version
    ContainerdVersion = var.containerd_version != null ? var.containerd_version : ""

  }
}
