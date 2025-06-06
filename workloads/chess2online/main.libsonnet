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
        name: 'chess2online',
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            app: 'chess2online',
          },
        },
        template: {
          metadata: {
            labels: {
              app: 'chess2online',
            },
          },
          spec: {
            containers: [
              {
                name: 'chess2online',
                image: 'registry.gitlab.com/cgamesplay/chess2online:latest',
                ports: [
                  {
                    containerPort: 4000,
                  },
                ],
                resources: {
                  limits: {
                    memory: '128Mi',
                  },
                },
                volumeMounts: [
                  {
                    name: 'config',
                    mountPath: '/app/config/production.json',
                    subPath: 'production.json',
                  },
                  {
                    name: 'data',
                    mountPath: '/app/db',
                  },
                ],
              },
            ],
            imagePullSecrets: [
              {
                name: 'chess2online-registry',
              },
            ],
            volumes: [
              {
                name: 'config',
                secret: {
                  secretName: 'chess2online-config',
                },
              },
              {
                name: 'data',
                persistentVolumeClaim: {
                  claimName: 'chess2online-data',
                },
              },
            ],
          },
        },
      },
    },

    pvc: {
      apiVersion: 'v1',
      kind: 'PersistentVolumeClaim',
      metadata: {
        name: 'chess2online-data',
      },
      spec: {
        accessModes: ['ReadWriteOnce'],
        resources: {
          requests: {
            storage: '1Gi',
          },
        },
      },
    },

    serviceIngress: utils.service_ingress(config, { name: 'chess2online' }, 'chess2online', 4000, host='api.chess2online.com'),
  },
}
