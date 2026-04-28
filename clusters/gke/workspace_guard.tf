locals {
  using_default_workspace = terraform.workspace == "default"
}

resource "null_resource" "block_default_workspace" {
  count = local.using_default_workspace ? 1 : 0

  lifecycle {
    prevent_destroy = true
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "ERROR: You are using the default Terraform workspace."
      echo "Please create a ticket workspace, e.g.:"
      echo "Terraform workspace new FD-12345"
      exit 1
    EOT
  }
}
