variable "api_image_tag" {
  description = "Docker tag to use for LibreChat API"
  default     = "latest"
}

job "librechat" {
  datacenters = ["nbg1"]
  type        = "service"
  priority    = 50

  group "main" {
    network {
      mode = "bridge"
      port "http" {
        to = 3080
      }
    }

    service {
      name = NOMAD_JOB_NAME
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.${NOMAD_JOB_NAME}.tls.certresolver=le",
      ]

      check {
        type     = "http"
        path     = "/"
        interval = "30s"
        timeout  = "10s"
      }
    }

    task "api" {
      driver = "docker"
      config {
        image = "ghcr.io/danny-avila/librechat-dev-api:${var.api_image_tag}"
        ports = ["http"]
        
        volumes = [
          "/opt/librechat/config:/app/librechat.yaml",
          "/opt/librechat/images:/app/client/public/images",
          "/opt/librechat/uploads:/app/uploads",
          "/opt/librechat/logs:/app/api/logs"
        ]
      }

      vault {
        policies = ["librechat"]
      }

      template {
        destination = "secrets/env"
        env         = true
        data        = <<-EOF
          HOST=0.0.0.0
          NODE_ENV=production
          PORT=3080
          SEARCH=false
          ALLOW_EMAIL_LOGIN=true
          ALLOW_REGISTRATION=false
          {{ with secret "kv/librechat/env" }}
          OPENAI_API_KEY={{ .Data.OPENAI_API_KEY }}
          ANTHROPIC_API_KEY={{ .Data.ANTHROPIC_API_KEY }}
          GOOGLE_SEARCH_API_KEY={{ .Data.GOOGLE_SEARCH_API_KEY }}
          GOOGLE_CSE_ID={{ .Data.GOOGLE_CSE_ID }}
          TAVILY_API_KEY={{ .Data.TAVILY_API_KEY }}
          CREDS_KEY={{ .Data.CREDS_KEY }}
          CREDS_IV={{ .Data.CREDS_IV }}
          JWT_SECRET={{ .Data.JWT_SECRET }}
          JWT_REFRESH_SECRET={{ .Data.JWT_REFRESH_SECRET }}
          {{ end }}
          # MongoDB connection
          MONGO_URI=mongodb://127.0.0.1:27017/LibreChat
        EOF
      }

      resources {
        memory     = 196
        memory_max = 256
      }
    }

    task "mongodb" {
      driver = "docker"
      config {
        image = "mongo"
        command = "mongod"
        args = ["--noauth"]
        volumes = [
          "/opt/librechat/mongodb:/data/db"
        ]
      }

      resources {
        memory     = 256
        memory_max = 384
      }
    }
  }
}
