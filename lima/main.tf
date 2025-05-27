terraform {
  backend "kubernetes" {
    secret_suffix = "state"
    namespace     = "terraform"
  }
}

module "cluster" {
  source  = "../manifests"
  domain  = "lvh.me"
  verbose = true
}
