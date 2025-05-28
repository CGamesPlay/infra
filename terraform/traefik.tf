resource "helm_release" "traefik" {
  name          = "traefik"
  repository    = "https://traefik.github.io/charts"
  chart         = "traefik"
  namespace     = kubernetes_namespace.admin.metadata[0].name
  wait_for_jobs = true

  // https://github.com/traefik/traefik-helm-chart/blob/master/traefik/values.yaml
  set {
    name  = "ports.web.redirections.entryPoint.to"
    value = "websecure"
  }
  set {
    name  = "ports.web.redirections.entryPoint.scheme"
    value = "https"
  }
  set {
    name  = "ports.web.redirections.entryPoint.permanent"
    value = true
  }
  set {
    name  = "ports.websecure.asDefault"
    value = true
  }
  set {
    name  = "ports.metrics"
    value = "null"
  }
  set {
    name  = "ingressRoute.dashboard.enabled"
    value = true
  }
  set {
    name  = "ingressRoute.dashboard.matchRule"
    value = "Host(`traefik.${var.domain}`)"
  }
  set {
    name  = "ingressRoute.dashboard.entryPoints[0]"
    value = "websecure"
  }
  set {
    name  = "ingressRoute.dashboard.middlewares[0].name"
    value = local.auth_middleware
  }
  set {
    name  = "providers.kubernetesCRD.allowCrossNamespace"
    value = true
  }
  set {
    name  = "metrics.prometheus"
    value = "null"
  }
  set {
    name  = "globalArguments"
    value = "null"
  }
  set {
    name  = "logs.general.level"
    value = var.verbose ? "DEBUG" : "INFO"
  }
  set {
    name  = "logs.access.enabled"
    value = true
  }
}
