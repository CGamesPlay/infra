{
  driver: 'kapp',
  priority: 10,

  manifests(_config): {
    local module = self,
    local config = {
      email: error 'email required for LetsEncrypt',
    } + _config,
    local manifests = std.parseYaml(importstr 'cert-manager.yml'),

    vendor: manifests,
    clusterIssuer: {
      apiVersion: 'cert-manager.io/v1',
      kind: 'ClusterIssuer',
      metadata: {
        name: 'letsencrypt',
      },
      spec: {
        acme: {
          email: config.email,
          server: 'https://acme-staging-v02.api.letsencrypt.org/directory',
          privateKeySecretRef: { name: 'cert-manager-key' },
          solvers: [
            {
              http01: {
                ingress: { ingressClassName: 'traefik' },
              },
            },
          ],
        },
      },
    },
  },
}
