terraform {
  backend "kubernetes" {
    secret_suffix = "state"
    namespace     = "terraform"
  }
}

module "cluster" {
  source = "../terraform"

  domain        = "lvh.me"
  verbose       = true
  admin_secrets = "${path.module}/admin-secrets.yml"
  workloads = {
    whoami    = {}
    dashboard = {}
  }
}
