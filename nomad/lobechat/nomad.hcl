variable "image_tag" {
  description = "Docker tag to use for lobehub/lobe-chat"
  default     = "v1.1.3"
}

job "lobechat" {
  datacenters = ["nbg1"]
  type        = "service"
  priority    = 50

  group "main" {
    network {
      mode = "bridge"
      port "http" {
        to = 3210
      }
    }

    service {
      name = NOMAD_JOB_NAME
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.$${NOMAD_JOB_NAME}.tls.certresolver=le",
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
        image = "lobehub/lobe-chat:${var.image_tag}"
        ports = ["http"]
      }

      vault {
        policies = ["lobechat"]
      }

      template {
        destination = "secrets/env"
        env         = true
        data        = <<-EOF
          {{ with secret "kv/lobechat/env" }}
          OPENAI_API_KEY={{ .Data.OPENAI_API_KEY }}
          ANTHROPIC_API_KEY={{ .Data.ANTHROPIC_API_KEY }}
          ACCESS_CODE={{ .Data.ACCESS_CODE }}
          {{ end }}
          EOF
      }

      resources {
        memory     = 64
        memory_max = 256
      }
    }
  }
}
