job "backup" {
  datacenters = ["nbg1"]
  type = "batch"
  priority = 90

  periodic {
    // Run once a month at midnight in the morning of the first of the month
    cron = "@monthly"
  }

  group "main" {
    restart {
      delay = "1h"
    }

    ephemeral_disk {
      sticky = true
      migrate = true
    }

    task "restic" {
      driver = "raw_exec"
      config {
        command = "bash"
        args = ["secrets/do-backup.sh"]
      }

      vault {
        policies = ["backup-cluster"]
      }

      template {
        destination = "secrets/env"
        env = true
        data = <<-EOF
          {{ with secret "kv/backup/repository" }}
          AWS_ACCESS_KEY_ID={{ .Data.aws_access_key_id }}
          AWS_SECRET_ACCESS_KEY={{ .Data.aws_secret_access_key }}
          RESTIC_REPOSITORY={{ .Data.restic_repository }}
          RESTIC_PASSWORD={{ .Data.restic_password }}
          RESTIC_CACHE_DIR={{ env "NOMAD_ALLOC_DIR" }}
          {{ end }}
          EOF
      }

      template {
        destination = "local/excludes.txt"
        data = <<-EOF
          # Ignore allocation ephemeral storage
          /opt/nomad/alloc
          # Ignore docker registry (can be rebuilt if necessary)
          /opt/registry
          EOF
      }

      template {
        destination = "secrets/do-backup.sh"
        perms = "755"
        data = <<-EOF
        #!/bin/bash
        set -uexo pipefail
        restic version
        wg-quick save /etc/wireguard/wg0.conf
        restic backup --verbose /opt /etc /home/ubuntu --exclude-file=local/excludes.txt
        # This is pressently commented out because it has no effect yet.
        # Ideally, restic 0.12 will be installed when uncommenting it, since
        # that has substantial prune performance improvements.
        # restic forget --keep-monthly=12 --prune
        EOF
      }
    }
  }
}
