local core = import 'core/main.libsonnet';
local utils = import 'utils.libsonnet';

local app_ini = (
  function()
    local template = importstr 'app.ini';
    template
)();

{
  priority: 100,

  manifests(_config):
    local config = {
      image_tag: '4',
    } + _config;
    {
      local module = self,

      deployment: {
        apiVersion: 'apps/v1',
        kind: 'Deployment',
        metadata: {
          name: 'romm',
        },
        spec: {
          replicas: 1,
          strategy: {
            type: 'Recreate',
          },
          selector: {
            matchLabels: {
              app: 'romm',
            },
          },
          template: {
            metadata: {
              labels: {
                app: 'romm',
              },
            },
            spec: {
              enableServiceLinks: false,
              initContainers: [
                {
                  name: 'init-config',
                  image: 'busybox:latest',
                  command: ['sh', '-c', 'touch /romm/config/config.yml'],
                  volumeMounts: [
                    {
                      name: 'assets',
                      mountPath: '/romm/config',
                      subPath: 'config',
                    },
                  ],
                },
              ],
              containers: [
                {
                  name: 'romm',
                  image: 'rommapp/romm:' + config.image_tag,
                  ports: [
                    { containerPort: 8080 },
                  ],
                  volumeMounts: [
                    {
                      name: 'cache',
                      mountPath: '/romm/resources',
                      subPath: 'resources',
                    },
                    {
                      name: 'cache',
                      mountPath: '/redis-data',
                      subPath: 'redis-data',
                    },
                    {
                      name: 'assets',
                      mountPath: '/romm/library',
                      subPath: 'library',
                    },
                    {
                      name: 'assets',
                      mountPath: '/romm/assets',
                      subPath: 'assets',
                    },
                    {
                      name: 'assets',
                      mountPath: '/romm/config',
                      subPath: 'config',
                    },
                  ],
                  envFrom: [
                    { secretRef: { name: 'romm' } },
                  ],
                  env: [
                    { name: 'DB_HOST', value: '127.0.0.1' },
                    { name: 'DB_NAME', value: 'romm' },
                    { name: 'DB_USER', value: 'romm' },
                    { name: 'DB_PASSWD', value: 'romm' },
                    { name: 'DISABLE_USERPASS_LOGIN', value: 'true' },
                    { name: 'OIDC_ENABLED', value: 'true' },
                    { name: 'OIDC_PROVIDER', value: 'authelia' },
                    { name: 'OIDC_REDIRECT_URI', value: 'https://romm.' + config.domain + '/api/oauth/openid' },
                    { name: 'OIDC_SERVER_APPLICATION_URL', value: 'https://auth.' + config.domain + '/' },
                  ],
                  resources: {
                    requests: {
                      memory: '200Mi',
                    },
                    limits: {
                      memory: '512Mi',
                    },
                  },
                  startupProbe: {
                    httpGet: {
                      path: '/auth/logout',
                      port: 8080,
                    },
                    initialDelaySeconds: 45,
                    periodSeconds: 10,
                    timeoutSeconds: 5,
                    failureThreshold: 3,
                  },
                },
                {
                  name: 'mariadb',
                  image: 'mariadb:12',
                  env: [
                    { name: 'MARIADB_ALLOW_EMPTY_ROOT_PASSWORD', value: '1' },
                    { name: 'MARIADB_USER', value: 'romm' },
                    { name: 'MARIADB_PASSWORD', value: 'romm' },
                    { name: 'MARIADB_DATABASE', value: 'romm' },
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
                    { name: 'mariadb', mountPath: '/var/lib/mysql' },
                  ],
                },
              ],
              volumes: [
                {
                  name: 'assets',
                  persistentVolumeClaim: { claimName: 'romm-assets' },
                },
                {
                  name: 'cache',
                  persistentVolumeClaim: { claimName: 'romm-cache' },
                },
                {
                  name: 'mariadb',
                  persistentVolumeClaim: { claimName: 'romm-mariadb' },
                },
              ],
            },
          },
        },
      },

      pvcs: {
        assets: {
          apiVersion: 'v1',
          kind: 'PersistentVolumeClaim',
          metadata: {
            name: 'romm-assets',
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

        cache: {
          apiVersion: 'v1',
          kind: 'PersistentVolumeClaim',
          metadata: {
            name: 'romm-cache',
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

        mariadb: {
          apiVersion: 'v1',
          kind: 'PersistentVolumeClaim',
          metadata: {
            name: 'romm-mariadb',
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
      },

      serviceIngress: utils.simple_service(config, { app: 'romm', port: 8080 }),
    },
}
