# worker_nodes.tf
# Managed node group without Launch Template:
# - Avoids AL2023 bootstrap.sh/nodeadm issues
# - Lets EKS select the correct EKS-optimized AMI based on ami_type
# - Allows pinning a specific EKS optimized AMI "release_version" when needed

resource "aws_eks_node_group" "eks_nodes" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "${local.name_prefix}-nodes"
  node_role_arn   = aws_iam_role.eks_worker_role.arn
  subnet_ids      = var.subnet_ids

  # Choose OS family safely (EKS manages the correct EKS-optimized AMI)
  # Note: Bottlerocket is also "EKS optimized" but uses a different lifecycle than AL2/AL2023.
  ami_type = (
    var.node_os == "bottlerocket" ? "BOTTLEROCKET_x86_64" :
    var.node_os == "al2023"       ? "AL2023_x86_64_STANDARD" :
                                    "AL2_x86_64"
  )

  # Optional: pin a specific EKS-optimized AMI release (best way to reproduce “specific AMI build”).
  # For Bottlerocket, pinning is typically done by selecting a specific Bottlerocket variant/version;
  # many setups leave this unset so EKS tracks the recommended Bottlerocket AMI.
  release_version = (
    var.node_os == "bottlerocket" ? null :
    var.eks_ami_release_version != "" ? var.eks_ami_release_version : null
  )

  # Disk size is supported directly on managed node groups
  disk_size = var.disk_size

  # Instance type selection
  instance_types = [var.instance_type]

  scaling_config {
    desired_size = var.desired_size
    max_size     = var.max_size
    min_size     = var.min_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = local.common_tags

  depends_on = [
    aws_eks_cluster.eks,
    aws_iam_role_policy_attachment.eks_worker_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ec2_container_registry_read_only
  ]
}
