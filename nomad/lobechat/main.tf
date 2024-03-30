resource "vault_policy" "lobechat" {
  name   = "lobechat"
  policy = <<-EOT
    path "kv/lobechat/env" {
      capabilities = ["read"]
    }
  EOT
}

resource "nomad_job" "lobechat" {
  jobspec = file("${path.module}/nomad.hcl")
}
