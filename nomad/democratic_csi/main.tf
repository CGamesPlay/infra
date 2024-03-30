resource "nomad_job" "csi" {
  jobspec = file("${path.module}/nomad.hcl")
}
