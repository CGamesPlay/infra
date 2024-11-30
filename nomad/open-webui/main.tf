resource "vault_policy" "open-webui" {
  name   = "open-webui"
  policy = <<-EOT
    path "kv/open-webui/env" {
      capabilities = ["read"]
    }
  EOT
}

resource "nomad_job" "open-webui" {
  jobspec = file("${path.module}/nomad.hcl")
}
