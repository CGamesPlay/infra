resource "kubernetes_manifest" "traefik_config" {
  manifest = {
    apiVersion = "helm.cattle.io/v1"
    kind       = "HelmChartConfig"
    metadata = {
      name      = "traefik"
      namespace = "kube-system"
    }
    spec = {
      // https://github.com/traefik/traefik-helm-chart/blob/master/traefik/values.yaml
      valuesContent = yamlencode({
        ports = {
          web = {
            redirections = {
              entryPoint = {
                to        = "websecure"
                scheme    = "https"
                permanent = true
              }
            }
          }
          websecure = {
            asDefault = true
          }
          metrics = null
        }
        ingressRoute = {
          dashboard = {
            enabled     = true
            matchRule   = "Host(`traefik.${var.domain}`)"
            entryPoints = ["websecure"]
            middlewares = [{ name = local.auth_middleware }]
          }
        }
        providers = {
          kubernetesCRD = {
            allowCrossNamespace = true
          }
        }
        metrics = {
          prometheus = null
        }
        globalArguments = null
        logs = {
          general = {
            level = var.verbose ? "DEBUG" : "INFO"
          }
          access = {
            enabled = true
          }
        }
      })
    }
  }
}
