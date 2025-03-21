job "dashboard" {
  datacenters = ["nbg1"]
  type        = "service"

  update {
    canary       = 1
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
      name = NOMAD_JOB_NAME
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.$${NOMAD_JOB_NAME}.tls.certresolver=le",
        "traefik.http.routers.$${NOMAD_JOB_NAME}.rule=Host(`${base_domain}`)",
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
        change_mode = "noop"
        destination = "$${NOMAD_TASK_DIR}/site/index.html"
        data        = <<-EOF
        ${index_html}
        EOF
      }

      template {
        change_mode = "noop"
        destination = "$${NOMAD_TASK_DIR}/site/ca.crt"
        data        = <<-EOF
        {{- with secret "pki/cert/ca" -}}
        {{- .Data.certificate -}}
        {{- end -}}
        EOF
      }

      resources {
        memory = 10
      }
    }
  }
}
