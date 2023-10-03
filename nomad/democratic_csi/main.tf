resource "nomad_job" "csi" {
  jobspec = file("${path.module}/democratic-csi.hcl")
}
