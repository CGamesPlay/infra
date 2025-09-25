local utils = import '../utils.libsonnet';

{
  priority: 100,

  manifests(_config):
    local config = {
      // was 10.0.15
      image_tag: '12.0-latest',
    } + _config;
    {
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

      deployment: {
        apiVersion: 'apps/v1',
        kind: 'Deployment',
        metadata: {
          name: 'seafile',
        },
        spec: {
          replicas: 1,
          strategy: {
            // Seafile refuses to start if another server has a lock on the
            // data directory.
            type: 'Recreate',
          },
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
                  image: 'seafileltd/seafile-pro-mc:' + config.image_tag,
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
                  env: [
                    {
                      name: 'JWT_PRIVATE_KEY',
                      valueFrom: {
                        secretKeyRef: {
                          name: 'seafile',
                          key: 'JWT_PRIVATE_KEY',
                        },
                      },
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
                  image: 'mariadb:10.11',
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
                  image: 'memcached:1.6.18',
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

      serviceIngress: utils.simple_service(config, { app: 'seafile', port: 80 }),
    },
}
