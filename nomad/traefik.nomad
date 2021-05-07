job "traefik" {
  datacenters = ["nbg1"]

  group "main" {
    count = 1

    network {
      port "http" {
        static = 80
      }
      port "https" {
        static = 443
      }
      port "dashboard" {
        static = 8080
      }
    }

    volume "storage" {
      type = "host"
      source = "traefik"
    }

    service {
      name = "${NOMAD_JOB_NAME}"
      port = "https"

      check {
        type     = "tcp"
        port     = "http"
        interval = "30s"
        timeout  = "2s"
      }
    }

    task "traefik" {
      driver = "docker"

      config {
        image        = "traefik:v2.2"
        network_mode = "host"

        volumes = [
          "local/ca.crt:/etc/traefik/ca.crt",
          "local/traefik.toml:/etc/traefik/traefik.toml",
        ]
      }

      # A persistent storage for LetsEncrypt certificates isn't technically
      # necessary, but it's a bit more efficient if Traefik ever gets
      # restaarted for some reason.
      volume_mount {
        volume = "storage"
        destination = "/etc/traefik/acme"
      }

      template {
        destination = "local/traefik.toml"
        data = <<EOF
[entryPoints.http]
address = ":{{env "NOMAD_PORT_http"}}"
[entryPoints.http.http.redirections.entryPoint]
to = "https"
scheme = "https"

[entryPoints.https]
address = ":{{env "NOMAD_PORT_https"}}"

[entryPoints.traefik]
address = "172.30.0.1:{{env "NOMAD_PORT_dashboard"}}"

[certificatesResolvers.le.acme]
email = "contact@cgamesplay.com"
storage = "/etc/traefik/acme/acme.json"
[certificatesResolvers.le.acme.tlsChallenge]

[api]
# Expose the API directly. Note that we bind to the Wireguard IP directly for
# the traefik entryPoint.
insecure = true

# Enable Consul Catalog configuration backend.
[providers.consulCatalog]
exposedByDefault = false
defaultRule = "Host(`{{`{{normalize .Name}}`}}.{{ key "traefik/config/domain" }}`)"

[providers.consulCatalog.endpoint]
address = "127.0.0.1:8501"
scheme  = "https"
[providers.consulCatalog.endpoint.tls]
ca = "/etc/traefik/ca.crt"

[log]
level = "DEBUG"

[accesslog]
EOF
      }

      template {
        destination = "local/ca.crt"
        data = <<EOF
{{ with secret "pki/cert/ca"}}
{{ .Data.certificate }}
{{ end }}
EOF
      }

      resources {
        memory = 64
      }
    }
  }
}


