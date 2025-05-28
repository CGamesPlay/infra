locals {
  auth_middleware = "admin-authelia@kubernetescrd"
}

resource "kubernetes_deployment" "authelia" {
  metadata {
    name      = "authelia"
    namespace = kubernetes_namespace.admin.metadata[0].name
  }
  wait_for_rollout = false
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "authelia"
      }
    }
    template {
      metadata {
        labels = {
          app = "authelia"
        }
      }
      spec {
        enable_service_links = false
        container {
          name  = "authelia"
          image = "docker.io/authelia/authelia:latest"
          env_from {
            secret_ref {
              name = kubernetes_secret.authelia.metadata[0].name
            }
          }
          volume_mount {
            name       = "config"
            mount_path = "/config"
          }
          volume_mount {
            name       = "data"
            mount_path = "/var/lib"
          }
          resources {
            requests = {
              cpu    = "200m"
              memory = "128Mi"
            }
            limits = {
              memory = "512Mi"
            }
          }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.authelia.metadata[0].name
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.authelia.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_secret" "authelia" {
  metadata {
    generate_name = "authelia-"
    namespace     = kubernetes_namespace.admin.metadata[0].name
  }
  immutable = true

  data = {
    AUTHELIA_SESSION_SECRET                                = "CHANGE ME"
    AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET = "CHANGE ME"
    AUTHELIA_STORAGE_ENCRYPTION_KEY                        = "authelia is full of stupid restrictions CHANGE ME"
  }
}

resource "kubernetes_config_map" "authelia" {
  metadata {
    generate_name = "authelia-"
    namespace     = kubernetes_namespace.admin.metadata[0].name
  }
  immutable = true

  data = {
    "configuration.yml" = <<-EOF
      theme: 'auto'
      server:
        address: 'tcp://:9091'
      log:
        level: '${var.verbose ? "debug" : "info"}'
      authentication_backend:
        file:
          path: '/config/users.yml'
      access_control:
        default_policy: 'one_factor'
      session:
        cookies:
          - domain: '${var.domain}'
            authelia_url: 'https://auth.${var.domain}'
            inactivity: '1 day'
            expiration: '1 day'
      storage:
        local:
          path: '/var/lib/db.sqlite3'
      notifier:
        filesystem:
          filename: '/var/lib/notification.txt'
      EOF
    "users.yml"         = <<-EOF
      users:
        authelia:
          disabled: false
          displayname: 'Authelia User'
          # Password is authelia
          password: '$6$rounds=50000$BpLnfgDsc2WD8F2q$Zis.ixdg9s/UOJYrs56b5QEZFiZECu0qZVNsIYxBaNJ7ucIL.nlxVCT5tqh8KHG8X4tlwCFm5r6NTOZZ5qRFN/'
          email: 'ry@cgamesplay.com'
          groups:
            - 'admin'
      EOF
  }
}

resource "kubernetes_persistent_volume_claim" "authelia" {
  metadata {
    name      = "authelia"
    namespace = kubernetes_namespace.admin.metadata[0].name
  }
  wait_until_bound = false
  spec {
    storage_class_name = "local-path"
    access_modes       = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}

resource "kubernetes_service" "authelia" {
  metadata {
    name      = "authelia"
    namespace = kubernetes_namespace.admin.metadata[0].name
  }
  spec {
    selector = {
      app = "authelia"
    }
    port {
      port = 9091
    }
  }
}

resource "kubernetes_ingress_v1" "authelia" {
  metadata {
    name      = "authelia"
    namespace = kubernetes_namespace.admin.metadata[0].name
  }
  spec {
    rule {
      host = "auth.${var.domain}"
      http {
        path {
          backend {
            service {
              name = "authelia"
              port { number = 9091 }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_manifest" "authelia_middleware" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "authelia"
      namespace = kubernetes_namespace.admin.metadata[0].name
    }
    spec = {
      forwardAuth = {
        address             = "http://authelia.${kubernetes_namespace.admin.metadata[0].name}.svc.cluster.local:9091/api/authz/forward-auth"
        authResponseHeaders = ["Remote-User", "Remote-Groups", "Remote-Name", "Remote-Email"]
      }
    }
  }
}
