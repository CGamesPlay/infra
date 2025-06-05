local utils = import '../utils.libsonnet';

{
  priority: 100,

  manifests(config): {
    local module = self,

    configMap: utils.immutable_config_map({
      apiVersion: 'v1',
      kind: 'ConfigMap',
      metadata: {
        name: 'seafile-config-',
      },
      data: {
        MYSQL_ALLOW_EMPTY_PASSWORD: 'true',
        MYSQL_LOG_CONSOLE: 'true',
      },
    }),

    registrySecret: {
      apiVersion: 'v1',
      kind: 'Secret',
      metadata: {
        name: 'seafile-registry-secret',
      },
      type: 'kubernetes.io/dockerconfigjson',
      data: {
        '.dockerconfigjson': std.base64(std.manifestJsonMinified({
          auths: {
            'docker.seadrive.org': {
              username: 'seafile',
              password: 'zjkmid6rQibdZ=uJMuWS',
              auth: std.base64('seafile:zjkmid6rQibdZ=uJMuWS'),
            },
          },
        })),
      },
    },

    deployment: {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: {
        name: 'seafile',
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            app: 'seafile',
          },
        },
        template: {
          metadata: {
            labels: {
              app: 'seafile',
            },
          },
          spec: {
            imagePullSecrets: [
              { name: 'seafile-registry-secret' },
            ],
            containers: [
              {
                name: 'seafile',
                image: 'docker.seadrive.org/seafileltd/seafile-pro-mc',
                ports: [
                  {
                    containerPort: 80,
                    name: 'http',
                  },
                ],
                resources: {
                  requests: {
                    memory: '768Mi',
                  },
                  limits: {
                    memory: '2Gi',
                  },
                },
                volumeMounts: [
                  {
                    name: 'seafile-data',
                    mountPath: '/shared',
                  },
                ],
                livenessProbe: {
                  httpGet: {
                    path: '/api2/ping/',
                    port: 80,
                  },
                  initialDelaySeconds: 30,
                  periodSeconds: 30,
                  timeoutSeconds: 2,
                  failureThreshold: 3,
                },
                readinessProbe: {
                  httpGet: {
                    path: '/api2/ping/',
                    port: 80,
                  },
                  initialDelaySeconds: 5,
                  periodSeconds: 5,
                  timeoutSeconds: 2,
                },
              },
              {
                name: 'mariadb',
                image: 'mariadb:10.5',
                args: ['--datadir=/shared/mariadb'],
                envFrom: [
                  {
                    configMapRef: {
                      name: module.configMap.metadata.name,
                    },
                  },
                ],
                resources: {
                  requests: {
                    memory: '200Mi',
                  },
                  limits: {
                    memory: '200Mi',
                  },
                },
                volumeMounts: [
                  {
                    name: 'mariadb-data',
                    mountPath: '/shared/mariadb',
                  },
                ],
              },
              {
                name: 'memcached',
                image: 'memcached:1.5.6',
                command: ['memcached', '-m', '60'],
                resources: {
                  requests: {
                    memory: '64Mi',
                  },
                  limits: {
                    memory: '64Mi',
                  },
                },
              },
            ],
            volumes: [
              {
                name: 'seafile-data',
                persistentVolumeClaim: {
                  claimName: 'seafile-data',
                },
              },
              {
                name: 'mariadb-data',
                persistentVolumeClaim: {
                  claimName: 'mariadb-data',
                },
              },
            ],
          },
        },
      },
    },

    seafileDataPvc: {
      apiVersion: 'v1',
      kind: 'PersistentVolumeClaim',
      metadata: {
        name: 'seafile-data',
      },
      spec: {
        accessModes: ['ReadWriteOnce'],
        resources: {
          requests: {
            storage: '10Gi',
          },
        },
      },
    },

    mariadbDataPvc: {
      apiVersion: 'v1',
      kind: 'PersistentVolumeClaim',
      metadata: {
        name: 'mariadb-data',
      },
      spec: {
        accessModes: ['ReadWriteOnce'],
        resources: {
          requests: {
            storage: '5Gi',
          },
        },
      },
    },

    local S = utils.service_ingress({ name: 'seafile' }, 'seafile', 'seafile.' + config.domain, 80),
    service: S.service,
    ingress: S.ingress,
  },
}
