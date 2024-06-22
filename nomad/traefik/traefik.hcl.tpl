job "traefik" {
  datacenters = ["nbg1"]
  type        = "service"
  priority    = 90

  group "main" {
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

    restart {
      mode = "delay"
    }

    ephemeral_disk {
      sticky  = true
      migrate = true
    }

    service {
      name = NOMAD_JOB_NAME
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
        image        = "traefik:v2.11.5"
        network_mode = "host"

        volumes = [
          "local/ca.crt:/etc/traefik/ca.crt",
          "local/traefik.toml:/etc/traefik/traefik.toml",
          "local/acme:/etc/traefik/acme",
          "local/static.toml:/etc/traefik/static.toml"
        ]
      }

      template {
        destination = "local/traefik.toml"
        data        = <<-EOF
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
          email = "{{ key "traefik/config/email" }}"
          storage = "/etc/traefik/acme/acme.json"
          preferredChain = "ISRG Root X1"
          [certificatesResolvers.le.acme.tlsChallenge]

          [api]
          # Expose the API directly. Note that we bind to the Wireguard IP directly for
          # the traefik entryPoint.
          insecure = true

          # Enable some hard-coded configuration options
          [providers.file]
          filename = "/etc/traefik/static.toml"
          watch = false

          # Enable Consul Catalog configuration backend.
          [providers.consulCatalog]
          exposedByDefault = false
          defaultRule = "Host(`{{`{{normalize .Name}}`}}.${base_domain}`)"

          [providers.consulCatalog.endpoint]
          address = "127.0.0.1:8501"
          scheme  = "https"
          [providers.consulCatalog.endpoint.tls]
          ca = "/etc/traefik/ca.crt"

          [log]
          #level = "DEBUG"

          [accesslog]
          EOF
      }

      template {
        destination = "local/ca.crt"
        data        = <<-EOF
          {{ with secret "pki/cert/ca"}}
          {{ .Data.certificate }}
          {{ end }}
          EOF
      }

      template {
        destination = "local/static.toml"
        data        = <<-EOF
        [tcp.routers.nomad]
        service = "nomad"
        rule = "HostSNI(`nomad.${base_domain}`)"
        tls.passthrough = true

        [[tcp.services.nomad.loadBalancer.servers]]
        address = "127.0.0.1:4646"

        [tcp.routers.vault]
        service = "vault"
        rule = "HostSNI(`vault.${base_domain}`)"
        tls.passthrough = true

        [[tcp.services.vault.loadBalancer.servers]]
        address = "127.0.0.1:8200"

        {{ if keyExists "traefik/config/tunnel" }}
        [http.routers.tunnel]
        entryPoints = [ "https" ]
        service = "tunnel"
        rule = "Host(`tunnel.${base_domain}`)"
        tls.certresolver = "le"

        [[http.services.tunnel.loadBalancer.servers]]
        url = "http://{{ key "traefik/config/tunnel" }}/"
        {{ end }}
        EOF
      }

      resources {
        memory = 64
      }
    }
  }
}
