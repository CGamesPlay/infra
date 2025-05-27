resource "kubernetes_deployment" "whoami" {
  metadata {
    name = "whoami"
  }
  wait_for_rollout = false
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "whoami"
      }
    }
    template {
      metadata {
        labels = {
          app = "whoami"
        }
      }
      spec {
        container {
          name  = "whoami"
          image = "containous/whoami"
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
      }
    }
  }
}

resource "kubernetes_service" "whoami" {
  metadata {
    name = "whoami"
  }
  spec {
    selector = {
      app = "whoami"
    }
    port {
      port = 80
    }
  }
}

resource "kubernetes_ingress_v1" "whoami" {
  metadata {
    name = "whoami"
  }
  spec {
    rule {
      host = "whoami.${var.domain}"
      http {
        path {
          backend {
            service {
              name = "whoami"
              port { number = 80 }
            }
          }
        }
      }
    }
  }
}
