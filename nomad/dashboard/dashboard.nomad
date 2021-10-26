[[/* This is jobspec should be rendered with levant. */]]
job "dashboard" {
  datacenters = ["nbg1"]
  type = "service"

  update {
    canary = 1
    auto_promote = true
  }

  group "main" {
    network {
      mode = "bridge"
      port "http" {
        to = 8080
      }
    }

    service {
      name = "${NOMAD_JOB_NAME}"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.${NOMAD_JOB_NAME}.tls.certresolver=le",
        "traefik.http.routers.${NOMAD_JOB_NAME}.rule=Host(`[[ consulKey "traefik/config/domain" ]]`)",
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
        image = "halverneus/static-file-server"
        ports = ["http"]

        volumes = [
          "local/site:/web"
        ]
      }

      template {
        destination = "local/site/index.html"
        data = <<-EOF
        [[ fileContents "index.html" ]]
        EOF
      }

      resources {
        memory = 10
      }
    }
  }
}
