{
  priority: 10,

  manifests(_config): {
    local module = self,
    local config = {
      email: error 'email required for LetsEncrypt',
      staging: true,
      hostedZoneID: error 'hostedZoneID is required when using wildcardCertificate',
    } + _config,
    local manifests = std.parseYaml(importstr 'cert-manager.yml'),
    local server = if config.staging then
      'https://acme-staging-v02.api.letsencrypt.org/directory'
    else
      'https://acme-v02.api.letsencrypt.org/directory',


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
          server: server,
          privateKeySecretRef: { name: 'cert-manager-key' },
          solvers:
            [{
              http01: {
                ingress: { ingressClassName: 'traefik' },
              },
            }] +
            if config.wildcardCertificate then
              [{
                selector: {
                  dnsNames: ['*.' + config.domain, config.domain],
                },
                dns01: {
                  route53: {
                    region: 'eu-central-1',
                    hostedZoneID: config.hostedZoneID,
                    accessKeyIDSecretRef: {
                      name: 'aws-access-key',
                      key: 'AWS_ACCESS_KEY_ID',
                    },
                    secretAccessKeySecretRef: {
                      name: 'aws-access-key',
                      key: 'AWS_SECRET_ACCESS_KEY',
                    },
                  },
                },
              }]
            else [],
        },
      },
    },

    // The IngressRoute CRD that the Traefik dashboard uses doesn't cause
    // cert-manager to request certificates, so we do that part manually.
    traefikCertificate: if config.wildcardCertificate then {} else {
      apiVersion: 'cert-manager.io/v1',
      kind: 'Certificate',
      metadata: {
        name: 'traefik-tls',
        namespace: 'kube-system',
      },
      spec: {
        secretName: 'traefik-tls',
        dnsNames: ['traefik.' + config.domain],
        issuerRef: { name: 'letsencrypt' },
      },
    },
  },
}
