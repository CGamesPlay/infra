job "whoami" {
  datacenters = ["nbg1"]

  group "main" {
    count = 1

    network {
      port "http" {
        to = 80
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
        path     = "/"
        interval = "30s"
        timeout  = "2s"
      }
    }

    task "server" {
      driver = "docker"

      config {
        image = "containous/whoami"
        ports = ["http"]
      }

      resources {
        memory = 10
      }
    }
  }
}


