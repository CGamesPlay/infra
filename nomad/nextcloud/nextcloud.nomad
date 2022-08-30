[[/* This is jobspec should be rendered with levant. */]]
job "nextcloud" {
  datacenters = ["nbg1"]
  type = "service"

  group "main" {
    network {
      mode = "bridge"
      port "http" {
        to = "80"
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
        type = "http"
        path = "/"
        interval = "30s"
        timeout = "2s"
      }
    }

    task "nextcloud" {
      driver = "docker"
      config {
        image = "nextcloud:21-fpm-alpine"
        ports = ["api"]

        volumes = [
          "../alloc/html:/var/www/html"
        ]
      }

      template {
        destination = "secrets/env"
        env = true
        data = <<-EOF
        SQLITE_DATABASE=nextcloud # This means: /var/www/html/data/nextcloud.db
        TRUSTED_PROXIES={{ env "NOMAD_HOST_IP_http" }}
        NEXTCLOUD_ADMIN_USER=admin
        NEXTCLOUD_ADMIN_PASSWORD=password
        # The IP address is required so the Consul service checks don't get a
        # 400 error when hitting the endpoint.
        NEXTCLOUD_TRUSTED_DOMAINS={{ env "NOMAD_JOB_NAME" }}.{{ key "traefik/config/domain" }} {{ env "NOMAD_HOST_IP_http" }}
        EOF
      }
    }

    task "nginx" {
      driver = "docker"
      config {
        image = "nginx:alpine"

        volumes = [
          "local/nginx.conf:/etc/nginx/nginx.conf",
          "../alloc/html:/var/www/html:ro"
        ]
      }

      template {
        destination = "local/nginx.conf"
        data = <<-EOF
        [[fileContents "nginx.conf"]]
        EOF
      }
    }

    task "cron" {
      driver = "docker"
      config {
        image = "nextcloud:21-fpm-alpine"
        entrypoint = ["/cron.sh"]

        volumes = [
          "../alloc/html:/var/www/html"
        ]
      }
    }
  }
}
