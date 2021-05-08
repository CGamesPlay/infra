job "joplin" {
  datacenters = ["nbg1"]
  type = "service"

  group "main" {
    network {
      mode = "bridge"
      port "http" {
        to = 22300
      }
    }

    service {
      name = "${NOMAD_JOB_NAME}"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.${NOMAD_JOB_NAME}.tls.certresolver=le",
      ]

      check {
        type     = "http"
        path     = "/api/ping"
        interval = "30s"
        timeout  = "2s"
      }
    }

    task "server" {
      driver = "docker"
      config {
        image = "joplin/server"
        ports = ["http"]
      }

      template {
        destination = "secrets/env"
        env = true
        data = <<-EOF
        DB_CLIENT=pg
        APP_BASE_URL=https://{{ env "NOMAD_JOB_NAME" }}.{{ key "traefik/config/domain" }}
        EOF
      }

      resources {
        memory = 128
      }
    }

    task "postgres" {
      driver = "docker"
      config {
        image = "postgres:13-alpine"

        volumes = [
          "/opt/joplin/postgres:/var/lib/postgresql/data",
        ]
      }

      env {
        POSTGRES_USER = "joplin"
        POSTGRES_PASSWORD = "joplin"
        POSTGRES_DB = "joplin"
      }

      resources {
        memory = 32
      }

      lifecycle {
        hook = "prestart"
        sidecar = true
      }
    }
  }
}


