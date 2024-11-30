variable "image_tag" {
  description = "Docker tag to use for open-webui/open-webui"
  default     = "0.4.6"
}

job "open-webui" {
  datacenters = ["nbg1"]
  type        = "service"
  priority    = 50

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
      ]

      check {
        type     = "http"
        path     = "/health"
        interval = "30s"
        timeout  = "10s"
      }
    }

    task "server" {
      driver = "docker"
      config {
        image = "ghcr.io/open-webui/open-webui:${var.image_tag}"
        ports = ["http"]

        volumes = [
          "/opt/open-webui:/app/backend/data"
        ]
      }

      vault {
        policies = ["open-webui"]
      }

      template {
        destination = "secrets/env"
        env         = true
        data        = <<-EOF
          {{ with secret "kv/open-webui/env" }}
          WEBUI_SECRET_KEY={{ .Data.WEBUI_SECRET_KEY }}
          WEBUI_URL=https://${NOMAD_JOB_NAME}.cluster.cgamesplay.com/
          ENABLE_OLLAMA_API=False
          OPENAI_API_KEY={{ .Data.OPENAI_API_KEY }}
          ANTHROPIC_API_KEY={{ .Data.ANTHROPIC_API_KEY }}
          RAG_EMBEDDING_ENGINE=openai
          AUDIO_STT_ENGINE=openai

          # Doesn't work in version 0.4.6
          #ENABLE_RAG_WEB_SEARCH=True
          #RAG_WEB_SEARCH_ENGINE=serply
          #SERPLY_API_KEY={{ .Data.SERPLY_API_KEY }}
          {{ end }}
          EOF
      }

      resources {
        memory     = 512
        memory_max = 1024
      }
    }
  }
}
