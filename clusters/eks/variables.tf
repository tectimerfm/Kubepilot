# variables.tf (EKS)

variable "node_os" {
  description = "Node OS family: al2, al2023, or bottlerocket"
  type        = string
  default     = "al2023"
  validation {
    condition     = contains(["al2", "al2023", "bottlerocket"], var.node_os)
    error_message = "node_os must be either 'al2', 'al2023', or 'bottlerocket'."
  }
}

variable "eks_ami_release_version" {
  description = "Optional: pin an EKS-optimized AMI release version for the nodegroup. Leave empty for latest."
  type        = string
  default     = ""
}

variable "desired_size" {
  type = number
  default = 2
}

variable "min_size" {
  type = number
  default = 1
}

variable "max_size" {
  type = number
  default = 2
}


variable "instance_type" {
  description = "Instance type for the worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "disk_size" {
  description = "EBS volume size for worker nodes in GiB"
  type        = number
  default     = 20
}

variable "vpc_id" {
  description = "ID of the existing VPC"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs in the VPC"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for the EKS cluster"
  type        = list(string)
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.33"
}

variable "containerd_version" {
  description = "Optional: containerd version (for tracking/repro purposes). Containerd is determined by the selected EKS optimized AMI."
  type        = string
  default     = null
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-west-1"
}

variable "aws_profile" {
  description = "AWS CLI profile name (SSO). Leave empty to use default credential chain / AWS_PROFILE env var."
  type        = string
  default     = ""
}

##########################################################
####### Aqua Enforcer Helm (optional installation) #######
##########################################################

variable "install_aqua_enforcer" {
  type        = bool
  description = "Install Aqua Enforcer Helm chart?"
  default     = false
}

# NOTE: script auto-fills this based on flavour (eks/aks/gke)
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
