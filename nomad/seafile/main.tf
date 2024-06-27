resource "nomad_job" "seafile" {
  jobspec = file("${path.module}/nomad.hcl")
}
