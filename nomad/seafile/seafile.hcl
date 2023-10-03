job "seafile" {
  datacenters = ["nbg1"]
  type        = "service"
  priority    = 60

  group "main" {
    network {
      mode = "bridge"
      port "http" {
        to = 80
      }
    }

    task "seafile" {
      leader = true
      driver = "docker"
      config {
        image = "docker.seadrive.org/seafileltd/seafile-pro-mc"
        ports = ["http"]

        auth {
          username = "seafile"
          password = "zjkmid6rQibdZ=uJMuWS"
        }

        volumes = [
          "/opt/seafile/data:/shared",
        ]
      }

      resources {
        memory     = 512
        memory_max = 2048
      }

      service {
        name = NOMAD_JOB_NAME
        port = "http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.${NOMAD_JOB_NAME}.tls.certresolver=le",
        ]

        check {
          type                     = "http"
          path                     = "/api2/ping/"
          interval                 = "30s"
          timeout                  = "2s"
          failures_before_critical = 3
        }
      }
    }

    task "mariadb" {
      driver = "docker"
      config {
        image = "mariadb:10.5"

        volumes = [
          "/opt/seafile/mysql:/var/lib/mysql",
        ]
      }

      env {
        MYSQL_ALLOW_EMPTY_PASSWORD = true
        MYSQL_LOG_CONSOLE          = true
      }

      resources {
        memory = 200
      }

      lifecycle {
        hook    = "prestart"
        sidecar = true
      }
    }

    task "memcached" {
      driver = "docker"
      config {
        image      = "memcached:1.5.6"
        entrypoint = ["memcached", "-m", "60"]
      }

      resources {
        memory = 64
      }

      lifecycle {
        hook    = "prestart"
        sidecar = true
      }
    }
  }
}
