resource "nomad_csi_volume" "seafile" {
  plugin_id    = "democratic-csi"
  volume_id    = "seafile"
  name         = "seafile"
  capacity_min = "1GiB"
  capacity_max = "10GiB"

  capability {
    access_mode     = "single-node-writer"
    attachment_mode = "file-system"
  }
}

resource "nomad_job" "seafile" {
  jobspec = file("${path.module}/seafile.hcl")
}
