# variables.tf (AKS)

variable "azure_location" {
  description = "Azure region/location for AKS and resource group"
  type        = string
  default     = "eastus"
}

variable "azure_subscription_id" {
  description = "Optional: Azure subscription ID. Leave empty to use az CLI default subscription."
  type        = string
  default     = ""
}

variable "kubernetes_version" {
  description = "Optional: AKS Kubernetes version. If null, Azure chooses the default."
  type        = string
  default     = null
}

variable "containerd_version" {
  description = "Optional: containerd version label for tracking/repro purposes. AKS manages containerd via node image."
  type        = string
  default     = null
}

variable "node_count" {
  type    = number
  default = 2
}

variable "vm_size" {
  description = "AKS node VM size"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "node_os" {
  description = "Node OS family (AKS). Used to map to os_sku."
  type        = string
  default     = "ubuntu"
  validation {
    condition     = contains(["ubuntu", "azurelinux", "mariner"], var.node_os)
    error_message = "node_os must be one of: ubuntu, azurelinux, mariner."
  }
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
