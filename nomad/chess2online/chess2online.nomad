job "chess2online" {
  datacenters = ["nbg1"]
  type = "service"
  priority = 60

  group "main" {
    network {
      port "http" {
        to = 4000
      }
    }

    service {
      name = "${NOMAD_JOB_NAME}"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.${NOMAD_JOB_NAME}.tls.certresolver=le",
        "traefik.http.routers.${NOMAD_JOB_NAME}.rule=Host(`api.chess2online.com`)",
      ]

      check {
        type     = "http"
        path     = "/"
        interval = "30s"
        timeout  = "2s"
      }
    }

    task "server" {
      driver = "docker"
      config {
        image = "registry.cluster.cgamesplay.com/chess2:latest"
        ports = ["http"]

        volumes = [
          "secrets/config.json:/app/config/production.json",
          "/opt/chess2online:/app/db",
        ]
      }

      vault {
        policies = ["chess2online"]
      }

      template {
        destination = "secrets/config.json"
        data = <<-EOF
        {{ with secret "kv/chess2online/config" }}
        {
          "knex": {
            "client": "sqlite3",
            "connection": {
              "filename": "/app/db/production.sqlite3"
            },
            "useNullAsDefault": true
          },
          "auth": {
            "secret": "{{ .Data.secret }}"
          }
        }
        {{ end }}
        EOF
      }

      resources {
        memory = 128
      }
    }
  }
}


