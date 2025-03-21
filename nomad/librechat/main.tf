resource "vault_policy" "librechat" {
  name   = "librechat"
  policy = <<-EOT
    path "kv/librechat/env" {
      capabilities = ["read"]
    }
  EOT
}

resource "nomad_job" "librechat" {
  jobspec = file("${path.module}/nomad.hcl")
}