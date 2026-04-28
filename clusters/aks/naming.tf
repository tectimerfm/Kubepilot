resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

variable "ticket_id" {
  description = "Optional ticket identifier override. If empty, the Terraform workspace name is used."
  type        = string
  default     = ""
}

variable "user_tag" {
  description = "Short identifier for the user or team (e.g. support)."
  type        = string
  default     = "support"
}

locals {
  # Use ticket_id if provided, otherwise fall back to workspace
  effective_ticket = var.ticket_id != "" ? var.ticket_id : terraform.workspace

  # Normalize: lowercase and replace any non [a-z0-9-] with '-'
  ticket_safe = replace(lower(local.effective_ticket), "[^a-z0-9-]", "-")

  # Truncate ticket to avoid name length issues
  ticket_short = substr(local.ticket_safe, 0, 24)

  # Example: support-fd-65432-a1b2c3
  name_prefix = "${var.user_tag}-${local.ticket_short}-${random_string.suffix.result}"
}
