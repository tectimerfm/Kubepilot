terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0, < 7.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }

    null = {
      source  = "hashicorp/null"
      version = ">= 3.2"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20, < 4.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0, < 4.0"
    }
  }
}
