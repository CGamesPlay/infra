terraform {
  cloud {
    organization = "cgamesplay"

    workspaces {
      name = "nomad"
    }
  }


  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "2.4.0"
    }
    nomad = {
      source  = "hashicorp/nomad"
      version = "2.0.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "3.20.1"
    }
  }

  required_version = ">= 0.14.9"
}

provider "nomad" {
  ca_file = "./ca.crt"
}

provider "vault" {
  ca_cert_file = "./ca.crt"
}

variable "datacenter" {
  type        = string
  description = "internal name of the target data center"
  default     = "nbg1"
  nullable    = false
}

variable "base_domain" {
  type        = string
  description = "main domain name for traefik rules"
  nullable    = false
  default     = "example.com"
}

resource "nomad_scheduler_config" "config" {
  scheduler_algorithm             = "binpack"
  memory_oversubscription_enabled = true
  preemption_config = {
    batch_scheduler_enabled    = false
    service_scheduler_enabled  = false
    sysbatch_scheduler_enabled = false
    system_scheduler_enabled   = false
  }
}

module "backup" {
  source = "./backup"
}

module "dashboard" {
  source      = "./dashboard"
  base_domain = var.base_domain
}

module "lobechat" {
  source = "./lobechat"
  count = 0
}

module "open-webui" {
  source = "./open-webui"
}

module "librechat" {
  source = "./librechat"
}

module "seafile" {
  source = "./seafile"
}

module "traefik" {
  source      = "./traefik"
  base_domain = var.base_domain
}

module "whoami" {
  source = "./whoami"
  count  = 0
}
