terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
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

variable "admin_secrets" {
  type        = string
  description = "Contents of the environment's admin-secrets.yml file"
}

variable "authelia_users" {
  type        = string
  description = "Contents of the environment's authelia-users.yml file"
}

variable "workloads" {
  type        = map(any)
  description = "Enabled workloads and their settings"
}

resource "kubernetes_namespace" "admin" {
  metadata {
    name = "admin"
  }
}

resource "kubernetes_manifest" "admin_secrets" {
  depends_on = [kubernetes_namespace.admin]
  manifest   = yamldecode(var.admin_secrets)
}

module "backup" {
  count  = lookup(var.workloads, "backup", null) != null ? 1 : 0
  source = "./backup"

  namespace = kubernetes_namespace.admin.metadata[0].name
}

module "dashboard" {
  count  = lookup(var.workloads, "dashboard", null) != null ? 1 : 0
  source = "./dashboard"

  auth_middleware = local.auth_middleware
  domain          = var.domain
}

module "whoami" {
  count  = lookup(var.workloads, "whoami", null) != null ? 1 : 0
  source = "./whoami"

  domain = var.domain
}
