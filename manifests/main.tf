terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.2.4"
    }
  }
}

variable "domain" {
  type        = string
  description = "DNS suffix for all domains"
}

variable "verbose" {
  type        = bool
  description = "Enable verbose logging for core services"
  default     = false
}

resource "null_resource" "bootstrap" {
  depends_on = [helm_release.traefik]
}
