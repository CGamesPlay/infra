[[/* This is jobspec should be rendered with levant. */]]
job "launa" {
  datacenters = ["nbg1"]
  type = "service"
  priority = 60

  update {
    canary = 1
    auto_promote = true
  }

  [[/*
  // This works, but isn't really desirable unless actually working directly
  // with the service.
  meta {
    // This is used so that the job always redeploys.
    started_at = "[[ timeNow ]]"
  }
  */]]

  group "main" {
    network {
      port "http" {
        to = 3000
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
        image = "registry.[[ consulKey "traefik/config/domain" ]]/launa"
        ports = ["http"]
        init = true

        volumes = [
          "/opt/launa:/opt/launa",
        ]
      }

      vault {
        policies = ["launa"]
      }

      template {
        destination = "secrets/env"
        env = true
        data = <<-EOF
          {{ with secret "kv/launa/config" }}
          DATABASE_URL=sqlite:/opt/launa/production.sqlite3
          NEXTAUTH_SECRET={{ .Data.nextauthSecret }}
          NEXTAUTH_URL=https://{{ env "NOMAD_JOB_NAME" }}.[[ consulKey "traefik/config/domain" ]]/
          GOOGLE_CLIENT_ID={{ .Data.googleClientId }}
          GOOGLE_CLIENT_SECRET={{ .Data.googleClientSecret }}
          OPENWEATHER_KEY={{ .Data.openweatherKey }}
          LOG_LEVEL=trace
          {{ end }}
          EOF
      }

      resources {
        memory = 128
      }
    }
  }
}


