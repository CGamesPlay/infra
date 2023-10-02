resource "vault_policy" "backup" {
  name   = "backup-cluster"
  policy = <<-EOT
    path "kv/backup/repository" {
      capabilities = ["read"]
    }
  EOT
}

resource "nomad_job" "backup" {
  jobspec = file("${path.module}/backup.hcl")
}
