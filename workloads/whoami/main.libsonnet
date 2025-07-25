local utils = import 'utils.libsonnet';

{
  priority: 100,

  manifests(_config): {
    local module = self,
    local config = {} + _config,

    deployment: {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: {
        name: 'whoami',
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            app: 'whoami',
          },
        },
        template: {
          metadata: {
            labels: {
              app: 'whoami',
            },
          },
          spec: {
            containers: [
              {
                name: 'whoami',
                image: 'traefik/whoami',
                resources: {
                  limits: {
                    memory: '50Mi',
                  },
                },
              },
            ],
          },
        },
      },
    },

    serviceIngress: utils.service_ingress(config, { name: 'whoami' }, 'whoami', 80),

  },
}
