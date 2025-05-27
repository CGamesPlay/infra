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
