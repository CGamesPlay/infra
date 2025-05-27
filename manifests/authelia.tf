resource "kubernetes_deployment" "authelia" {
  metadata {
    name      = "authelia"
    namespace = kubernetes_namespace.authelia.metadata[0].name
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
              name = kubernetes_secret.authelia_secret.metadata[0].name
            }
          }
          volume_mount {
            name       = "config"
            mount_path = "/config"
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
            name = kubernetes_config_map.authelia_config.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_namespace" "authelia" {
  metadata {
    name = "authelia"
  }
}

resource "kubernetes_secret" "authelia_secret" {
  metadata {
    generate_name = "authelia-secret-"
    namespace     = kubernetes_namespace.authelia.metadata[0].name
  }
  immutable = true

  data = {
    AUTHELIA_SESSION_SECRET                                = "CHANGE ME"
    AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET = "CHANGE ME"
    AUTHELIA_STORAGE_ENCRYPTION_KEY                        = "authelia is full of stupid restrictions CHANGE ME"
  }
}

resource "kubernetes_config_map" "authelia_config" {
  metadata {
    generate_name = "authelia-config-"
    namespace     = kubernetes_namespace.authelia.metadata[0].name
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
          path: '/tmp/db.sqlite3'
      notifier:
        filesystem:
          filename: '/tmp/notification.txt'
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

resource "kubernetes_service" "authelia" {
  metadata {
    name      = "authelia"
    namespace = kubernetes_namespace.authelia.metadata[0].name
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
    namespace = kubernetes_namespace.authelia.metadata[0].name
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
      namespace = kubernetes_namespace.authelia.metadata[0].name
    }
    spec = {
      forwardAuth = {
        address             = "http://authelia.${kubernetes_namespace.authelia.metadata[0].name}.svc.cluster.local:9091/api/authz/forward-auth"
        authResponseHeaders = ["Remote-User", "Remote-Groups", "Remote-Name", "Remote-Email"]
      }
    }
  }
}
