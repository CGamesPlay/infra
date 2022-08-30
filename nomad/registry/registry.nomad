[[/* This is jobspec should be rendered with levant. */]]
job "registry" {
  datacenters = ["nbg1"]
  type = "service"
  priority = 60

  group "main" {
    network {
      port "http" {
        to = 5000
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
        image = "registry:2"
        ports = ["http"]

        volumes = [
          "/opt/registry:/var/lib/registry",
          "local/config.yml:/etc/docker/registry/config.yml",
          "local/htpasswd:/etc/docker/registry/htpasswd"
        ]
      }

      vault {
        policies = ["docker"]
      }

      template {
        destination = "local/config.yml"
        data = <<-EOF
        version: 0.1
        storage:
          filesystem:
            rootdirectory: /var/lib/registry
          delete:
            enabled: true
        http:
          addr: 0.0.0.0:5000
        auth:
          htpasswd:
            realm: {{ env "NOMAD_JOB_NAME" }}.{{ key "traefik/config/domain" }}
            path: /etc/docker/registry/htpasswd
        EOF
      }

      template {
        destination = "local/htpasswd"
        data = <<-EOF
        {{- with secret "kv/docker/users" -}}
        {{- .Data.htpasswd }}
        {{ end -}}
        EOF
      }

      resources {
        memory = 32
      }
    }
  }
}


