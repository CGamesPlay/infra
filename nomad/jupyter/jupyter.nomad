job "jupyter" {
  datacenters = ["nbg1"]
  type = "service"
  priority = 50

  group "main" {
    network {
      mode = "bridge"
      port "http" {
        to = 8888
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
        image = "jupyter/tensorflow-notebook"
        ports = ["http"]

        volumes = [
          "/opt/jupyter/data:/home/jovyan/work",
          "secrets/jupyter_server_config.json:/home/jovyan/.jupyter/jupyter_server_config.json"
        ]
      }

      vault {
        policies = ["jupyter"]
      }

      template {
        destination = "secrets/jupyter_server_config.json"
        # cull_idle_timeout - Kill idle kernels after 48 hours
        data = <<-EOF
        {{ with secret "kv/jupyter/config" }}
        {
          "ServerApp": {
            "password": "{{ .Data.password_hash }}",
            "quit_button": false,
            "notebook_dir": "work"
          },
          "MappingKernelManager": {
            "cull_idle_timeout": 172800
          }
        }
        {{ end }}
        EOF
      }

      resources {
        memory = 500
      }
    }
  }
}


