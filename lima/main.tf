terraform {
  backend "kubernetes" {
    secret_suffix = "state"
    namespace     = "terraform"
  }
}

module "cluster" {
  source = "../terraform"

  domain         = "lvh.me"
  verbose        = true
  admin_secrets  = file("${path.module}/admin-secrets.yml")
  authelia_users = file("${path.module}/authelia-users.yml")
  workloads = {
    whoami    = {}
    dashboard = {}
  }
}
