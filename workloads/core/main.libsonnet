local utils = import 'utils.libsonnet';

{
  auth_middleware: 'admin-authelia@kubernetescrd',

  priority: 0,

  manifests(_config): {
    local module = self,
    local config = {
      verbose: false,
    } + _config,

    sopsSecrets: {
      [std.get(x.metadata, 'namespace', 'default') + ':' + x.metadata.name]: x
      for x in std.parseYaml(config.secrets)
    },

    traefikChartConfig: {
      apiVersion: 'helm.cattle.io/v1',
      kind: 'HelmChartConfig',
      metadata: {
        name: 'traefik',
        namespace: 'kube-system',
      },
      spec: {
        valuesContent: std.manifestYamlDoc({
          ports: {
            web: {
              redirections: {
                entryPoint: {
                  to: 'websecure',
                  scheme: 'https',
                  permanent: true,
                },
              },
            },
            websecure: {
              asDefault: true,
            },
            metrics: null,
          },
          ingressRoute: {
            dashboard: {
              enabled: true,
              matchRule: 'Host(`traefik.' + config.domain + '`)',
              entryPoints: ['websecure'],
              middlewares: [{ name: $.auth_middleware }],
              // NOTE: certificate is manually requested in cert-manager
              // workload.
              tls: if config.wildcardCertificate then
                { secretName: 'tls-' + config.domain }
              else
                { secretName: 'traefik-tls' },
            },
          },
          providers: {
            kubernetesCRD: {
              allowCrossNamespace: true,
            },
          },
          metrics: {
            prometheus: null,
          },
          globalArguments: null,
          logs: {
            general: {
              level: if config.verbose then 'DEBUG' else 'INFO',
            },
            access: {
              enabled: true,
            },
          },
        }),
      },
    },

    adminNamespace: {
      apiVersion: 'v1',
      kind: 'Namespace',
      metadata: {
        name: 'admin',
      },
    },

    autheliaConfig: utils.immutable_config_map({
      apiVersion: 'v1',
      kind: 'ConfigMap',
      metadata: {
        namespace: 'admin',
        name: 'authelia-',
      },
      data: {
        'configuration.yml': std.manifestYamlDoc({
          theme: 'auto',
          server: { address: 'tcp://:9091' },
          log: { level: if config.verbose then 'debug' else 'info' },
          authentication_backend: {
            file: { path: '/config/users.yml' },
          },
          access_control: {
            default_policy: 'one_factor',
          },
          session: {
            cookies: [
              {
                domain: config.domain,
                authelia_url: 'https://authelia.' + config.domain,
                inactivity: '1 day',
                expiration: '1 day',
              },
            ],
          },
          storage: {
            'local': { path: '/var/lib/db.sqlite3' },
          },
          notifier: {
            filesystem: { filename: '/var/lib/notification.txt' },
          },
        }),
        'users.yml': config.authelia_users_yaml,
      },
    }),

    autheliaVolume: {
      apiVersion: 'v1',
      kind: 'PersistentVolumeClaim',
      metadata: {
        namespace: 'admin',
        name: 'authelia',
      },
      spec: {
        storageClassName: 'local-path',
        accessModes: ['ReadWriteOnce'],
        resources: {
          requests: {
            storage: '1Gi',
          },
        },
      },
    },

    autheliaDeployment: {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: {
        name: 'authelia',
        namespace: 'admin',
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            app: 'authelia',
          },
        },
        template: {
          metadata: {
            labels: {
              app: 'authelia',
            },
          },
          spec: {
            enableServiceLinks: false,
            containers: [
              {
                name: 'authelia',
                image: 'docker.io/authelia/authelia:latest',
                envFrom: [
                  { secretRef: { name: 'authelia' } },
                ],
                volumeMounts: [
                  { name: 'config', mountPath: '/config' },
                  { name: 'data', mountPath: '/var/lib' },
                ],
                resources: {
                  limits: {
                    memory: '512Mi',
                  },
                },
              },
            ],
            volumes: [
              {
                name: 'config',
                configMap: { name: module.autheliaConfig.metadata.name },
              },
              {
                name: 'data',
                persistentVolumeClaim: { claimName: module.autheliaVolume.metadata.name },
              },
            ],
          },
        },
      },
    },

    autheliaServiceIngress: utils.service_ingress(config, { name: 'authelia', namespace: 'admin' }, 'authelia', 9091),

    autheliaMiddleware: {
      apiVersion: 'traefik.io/v1alpha1',
      kind: 'Middleware',
      metadata: {
        name: 'authelia',
        namespace: 'admin',
      },
      spec: {
        forwardAuth: {
          address: 'http://authelia.admin.svc.cluster.local:9091/api/authz/forward-auth',
          authResponseHeaders: ['Remote-User', 'Remote-Groups', 'Remote-Name', 'Remote-Email'],
        },
      },
    },
  },
}
