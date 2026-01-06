local autheliaConfig = import './authelia.libsonnet';
local utils = import 'utils.libsonnet';

{
  auth_middleware: 'admin-authelia@kubernetescrd',

  priority: 0,

  manifests(_config): {
    local module = self,
    local config = {
      verbose: false,
      authelia_tag: '4.39.15',
      // Additional mixin for the Authelia configuration.yml
      authelia_config: {},
      // Can be used to allocate additional TCP listeners, key is label, value
      // is port number.
      tcp_ports: {},
      // Use mailer+: { enabled: true, ... } to enable, and set the
      // smtp_passwd secret.
      mailer: {
        enabled: false,
        sender: 'Authelia <authelia@%s>' % _config.domain,
        address: error 'address is required',
        username: error 'username is required',
        identifier: _config.domain,
      },
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
          } + {
            [name]: {
              port: port,
              expose: {
                default: true,
              },
              exposedPort: port,
            }
            for name in std.objectFields(config.tcp_ports)
            for port in [config.tcp_ports[name]]
          },
          service: {
            spec: {
              externalTrafficPolicy: 'Local',
            },
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
        'configuration.yml': std.manifestYamlDoc(autheliaConfig(config) + config.authelia_config),
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
                image: 'docker.io/authelia/authelia:' + config.authelia_tag,
                env: [
                  { name: 'X_AUTHELIA_CONFIG', value: '/etc/authelia' },
                ],
                envFrom: [
                  { secretRef: { name: 'authelia' } },
                ],
                volumeMounts: [
                  {
                    name: 'secrets',
                    mountPath: '/etc/authelia/configuration.secret.yml',
                    subPath: 'configuration.secret.yml',
                  },
                  {
                    name: 'config',
                    mountPath: '/etc/authelia/configuration.yml',
                    subPath: 'configuration.yml',
                  },
                  { name: 'data', mountPath: '/var/lib/authelia' },
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
                name: 'secrets',
                secret: { secretName: 'authelia' },
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

    autheliaServiceIngress: utils.simple_service(config, { app: 'authelia', namespace: 'admin', port: 9091, host: 'auth.' + config.domain }),

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
