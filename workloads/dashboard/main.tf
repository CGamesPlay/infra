variable "auth_middleware" {
  type        = string
  description = "Name of authelia middleware"
}

variable "domain" {
  type        = string
  description = "DNS suffix for all domains"
}

resource "kubernetes_deployment" "dashboard" {
  metadata {
    name = "dashboard"
  }
  wait_for_rollout = false
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "dashboard"
      }
    }
    template {
      metadata {
        labels = {
          app = "dashboard"
        }
      }
      spec {
        container {
          name  = "dashboard"
          image = "halverneus/static-file-server"
          volume_mount {
            name       = "web-content"
            mount_path = "/web"
          }
          resources {
            requests = {
              cpu    = "200m"
              memory = "10Mi"
            }
            limits = {
              memory = "50Mi"
            }
          }
        }
        volume {
          name = "web-content"
          config_map {
            name = kubernetes_config_map.dashboard_files.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_config_map" "dashboard_files" {
  metadata {
    generate_name = "dashboard-files-"
  }
  immutable = true

  data = {
    "index.html" = templatefile("${path.module}/index.html.tftpl", {
      domain = var.domain
    })
  }
}

resource "kubernetes_service" "dashboard" {
  metadata {
    name = "dashboard"
  }
  spec {
    selector = {
      app = "dashboard"
    }
    port {
      port = 8080
    }
  }
}

resource "kubernetes_ingress_v1" "dashboard" {
  metadata {
    name = "dashboard"
    annotations = {
      "traefik.ingress.kubernetes.io/router.middlewares" = var.auth_middleware
    }
  }
  spec {
    rule {
      host = var.domain
      http {
        path {
          backend {
            service {
              name = "dashboard"
              port { number = 8080 }
            }
          }
        }
      }
    }
  }
}
