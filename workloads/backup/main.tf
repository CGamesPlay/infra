variable "namespace" {
  type = string
}

resource "kubernetes_cron_job_v1" "restic" {
  metadata {
    name      = "restic"
    namespace = var.namespace
  }

  spec {
    schedule = "@monthly"

    job_template {
      metadata {
        name      = "restic"
        namespace = var.namespace
      }

      spec {
        backoff_limit = 4

        template {
          metadata {
            name = "restic"
          }

          spec {
            restart_policy = "Never"

            container {
              name  = "backup"
              image = "alpine:latest"

              env_from {
                secret_ref {
                  name = "restic"
                }
              }

              volume_mount {
                name       = "restic-script"
                mount_path = "/app"
              }

              volume_mount {
                name       = "var-opt"
                mount_path = "/var/opt"
              }

              command = ["/app/backup.sh"]
            }

            volume {
              name = "restic-script"
              config_map {
                name         = kubernetes_config_map_v1.restic_script.metadata[0].name
                default_mode = "0755"
              }
            }

            volume {
              name = "var-opt"
              host_path {
                path = "/var/opt"
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_config_map_v1" "restic_script" {
  metadata {
    generate_name = "restic-script-"
    namespace     = var.namespace
  }
  immutable = true

  data = {
    "backup.sh" = file("${path.module}/backup.sh")
  }
}

