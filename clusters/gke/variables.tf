# variables.tf (GKE)

variable "project_id" {
  description = "GCP project id"
  type        = string
}

variable "region" {
  description = "GCP region for the cluster"
  type        = string
  default     = "us-central1"
}

variable "kubernetes_version" {
  description = "Optional: minimum master Kubernetes version (and node pool version if set). Leave null to let GKE choose."
  type        = string
  default     = null
}

variable "containerd_version" {
  description = "Optional: containerd version (for tracking/repro purposes). Containerd is determined by the selected node image (COS/Ubuntu)."
  type        = string
  default     = null
}

variable "node_count" {
  type    = number
  default = 2
}

variable "machine_type" {
  description = "GKE node machine type"
  type        = string
  default     = "e2-standard-2"
}

variable "node_os" {
  description = "Node OS family (GKE) mapped to image_type"
  type        = string
  default     = "cos"
  validation {
    condition     = contains(["cos", "ubuntu"], var.node_os)
    error_message = "node_os must be one of: cos, ubuntu."
  }
}

variable "network" {
  description = "VPC network name"
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "Optional: subnetwork name. If null, GKE uses default behavior."
  type        = string
  default     = null
}

##########################################################
####### Aqua Enforcer Helm (optional installation) #######
##########################################################

variable "install_aqua_enforcer" {
  type        = bool
  description = "Install Aqua Enforcer Helm chart?"
  default     = false
}

variable "aqua_platform" {
  type        = string
  description = "Platform identifier (eks, gke, aks)"
  default     = null
}

variable "aqua_enforcer_image_tag" {
  type        = string
  description = "Enforcer image tag (e.g., 2022.4.860.26). Optional."
  default     = null
}

variable "gateway_address" {
  type        = string
  description = "Aqua Gateway address/hostname (optional). If null, use chart default."
  default     = null
}

variable "gateway_port" {
  type        = number
  description = "Aqua Gateway port (optional). If null, use chart default."
  default     = null
}

variable "aqua_registry_username" {
  type        = string
  description = "Aqua registry username"
  sensitive   = true
  default     = null
}

variable "aqua_registry_password" {
  type        = string
  description = "Aqua registry password"
  sensitive   = true
  default     = null
}

variable "aqua_enforcer_token" {
  type        = string
  description = "Aqua Enforcer token"
  sensitive   = true
  default     = null
}
