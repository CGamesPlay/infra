resource "nomad_job" "whoami" {
  jobspec = file("${path.module}/whoami.hcl")
}
