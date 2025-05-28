terraform {
  backend "kubernetes" {
    secret_suffix = "state"
    namespace     = "terraform"
  }
}

resource "kubernetes_manifest" "admin_secrets" {
  manifest = yamldecode(file("${path.module}/admin-secrets.yml"))
}

module "cluster" {
  source  = "../manifests"
  domain  = "lvh.me"
  verbose = true
}
