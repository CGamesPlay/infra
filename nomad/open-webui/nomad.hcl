variable "image_tag" {
  description = "Docker tag to use for open-webui/open-webui"
  default     = "0.5.18"
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
          ANTHROPIC_API_KEY={{ .Data.ANTHROPIC_API_KEY }}
          # All of the following are PersistentConfig, so they theoretically
          # have no effect on existing containers.
          WEBUI_URL=https://${NOMAD_JOB_NAME}.cluster.cgamesplay.com/
          ENABLE_OLLAMA_API=False
          OPENAI_API_KEY={{ .Data.OPENAI_API_KEY }}
          RAG_EMBEDDING_ENGINE=openai
          AUDIO_STT_ENGINE=openai

          ENABLE_RAG_WEB_SEARCH=True
          RAG_WEB_SEARCH_ENGINE=google_pse
          RAG_WEB_SEARCH_RESULT_COUNT=3
          RAG_WEB_SEARCH_CONCURRENT_REQUESTS=10
          GOOGLE_PSE_API_KEY={{ .Data.GOOGLE_PSE_API_KEY }}
          GOOGLE_PSE_ENGINE_ID={{ .Data.GOOGLE_PSE_ENGINE_ID }}
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
