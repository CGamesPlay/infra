variable "base_domain" {
  type = string
}

resource "nomad_job" "traefik" {
  jobspec = templatefile("${path.module}/traefik.hcl.tpl", {
    base_domain = var.base_domain
  })
}
