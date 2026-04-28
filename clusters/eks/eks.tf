# eks.tf

resource "aws_eks_cluster" "eks" {
  name     = local.name_prefix
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  version    = var.kubernetes_version
  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]

  tags = local.common_tags
}

output "eks_cluster_name" {
  value = aws_eks_cluster.eks.name
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.eks.endpoint
}

output "eks_cluster_certificate_authority" {
  value = aws_eks_cluster.eks.certificate_authority[0].data
}

data "aws_vpc" "selected" {
  id = var.vpc_id
}
