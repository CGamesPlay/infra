job "traefik" {
  region      = "global"
  datacenters = ["nbg1"]
  type        = "service"

  group "traefik" {
    count = 1

    network {
      port "http" {
        static = 80
      }
    }

    service {
      name = "traefik"

      check {
        name     = "alive"
        type     = "tcp"
        port     = "http"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.traefik.service=api@internal",
      ]
    }

    task "traefik" {
      driver = "docker"

      config {
        image        = "traefik:v2.2"
        network_mode = "host"

        volumes = [
          "local/traefik.toml:/etc/traefik/traefik.toml",
        ]
      }

      template {
        data = <<EOF
[entryPoints]
    [entryPoints.http]
    address = ":{{env "NOMAD_PORT_http"}}"

[api]
    dashboard = true

# Enable Consul Catalog configuration backend.
[providers.consulCatalog]
    exposedByDefault = false
    defaultRule = "Host(`{{`{{normalize .Name}}`}}.service.consul`)"
    [providers.consulCatalog.endpoint]
      address = "127.0.0.1:8500"
      scheme  = "http"

[log]
    level = "DEBUG"
EOF

        destination = "local/traefik.toml"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}


