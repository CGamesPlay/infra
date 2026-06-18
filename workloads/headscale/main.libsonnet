local utils = import '../utils.libsonnet';

{
  priority: 100,

  manifests(_config):
    local config = {
      image_tag: 'v0.29',
      // IPv6 prefix within Tailscale's fd7a:115c:a1e0::/48 range
      prefixes_v6: 'fd7a:115c:a1e0:7939::/64',
      // MagicDNS base domain (must differ from server_url domain)
      dns_base_domain: 'ts.200-ok.link',
    } + _config;

    local serverUrl = 'https://headscale.' + config.domain;

    {
      local module = self,

      configMap: utils.immutable_config_map({
        apiVersion: 'v1',
        kind: 'ConfigMap',
        metadata: {
          name: 'headscale-config-',
        },
        data: {
          'config.yaml': std.manifestYamlDoc({
            server_url: serverUrl,
            listen_addr: '0.0.0.0:8080',
            metrics_listen_addr: '0.0.0.0:9090',
            noise: {
              private_key_path: '/var/lib/headscale/noise_private.key',
            },
            policy: {
              path: '/etc/headscale/policy.json',
            },
            prefixes: {
              v4: '100.64.0.0/10',
              v6: config.prefixes_v6,
            },
            database: {
              type: 'sqlite',
              sqlite: {
                path: '/var/lib/headscale/db.sqlite',
                write_ahead_log: true,
              },
            },
            derp: {
              server: {
                enabled: false,
              },
              urls: [
                'https://controlplane.tailscale.com/derpmap/default',
              ],
            },
            dns: {
              base_domain: config.dns_base_domain,
              override_local_dns: false,
            },
            oidc: {
              issuer: 'https://auth.' + config.domain,
              client_id: 'headscale',
              client_secret_path: '/run/secrets/oidc_client_secret',
              scope: ['openid', 'email', 'profile', 'groups'],
              pkce: {
                enabled: true,
                method: 'S256',
              },
              allowed_groups: ['network'],
            },
          }),
          'policy.json': std.manifestJson({
            nodeAttrs: [
              {
                target: ['*'],
                attr: ['magicdns-aaaa', 'dns-subdomain-resolve'],
              },
            ],
          }),
        },
      }),

      dataPvc: {
        apiVersion: 'v1',
        kind: 'PersistentVolumeClaim',
        metadata: {
          name: 'headscale-data',
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

      deployment: {
        apiVersion: 'apps/v1',
        kind: 'Deployment',
        metadata: {
          name: 'headscale',
        },
        spec: {
          replicas: 1,
          strategy: {
            type: 'Recreate',
          },
          selector: {
            matchLabels: {
              app: 'headscale',
            },
          },
          template: {
            metadata: {
              labels: {
                app: 'headscale',
              },
            },
            spec: {
              containers: [
                {
                  name: 'headscale',
                  image: 'docker.io/headscale/headscale:' + config.image_tag,
                  command: ['headscale', 'serve'],
                  ports: [
                    {
                      containerPort: 8080,
                      name: 'http',
                    },
                    {
                      containerPort: 9090,
                      name: 'metrics',
                    },
                  ],
                  volumeMounts: [
                    {
                      name: 'config',
                      mountPath: '/etc/headscale/config.yaml',
                      subPath: 'config.yaml',
                    },
                    {
                      name: 'config',
                      mountPath: '/etc/headscale/policy.json',
                      subPath: 'policy.json',
                    },
                    {
                      name: 'data',
                      mountPath: '/var/lib/headscale',
                    },
                    {
                      name: 'run',
                      mountPath: '/var/run/headscale',
                    },
                    {
                      name: 'oidc-secret',
                      mountPath: '/run/secrets/oidc_client_secret',
                      subPath: 'OIDC_CLIENT_SECRET',
                      readOnly: true,
                    },
                  ],
                  readinessProbe: {
                    exec: {
                      command: ['headscale', 'health'],
                    },
                    initialDelaySeconds: 5,
                    periodSeconds: 10,
                    timeoutSeconds: 5,
                    failureThreshold: 3,
                  },
                  livenessProbe: {
                    exec: {
                      command: ['headscale', 'health'],
                    },
                    initialDelaySeconds: 10,
                    periodSeconds: 30,
                    timeoutSeconds: 5,
                    failureThreshold: 3,
                  },
                  resources: {
                    requests: {
                      memory: '64Mi',
                    },
                    limits: {
                      memory: '256Mi',
                    },
                  },
                },
              ],
              volumes: [
                {
                  name: 'config',
                  configMap: {
                    name: module.configMap.metadata.name,
                  },
                },
                {
                  name: 'data',
                  persistentVolumeClaim: { claimName: module.dataPvc.metadata.name },
                },
                {
                  name: 'run',
                  emptyDir: {},
                },
                {
                  name: 'oidc-secret',
                  secret: { secretName: 'headscale' },
                },
              ],
            },
          },
        },
      },

      serviceIngress: utils.simple_service(config, { app: 'headscale', port: 8080 }),
    },
}
