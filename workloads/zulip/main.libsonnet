local utils = import '../utils.libsonnet';

{
  priority: 100,

  manifests(_config):
    local config = {
      image_tag: '12.2-0',
      admin_email: 'admin@zulip.' + _config.domain,
      // Sources trusted to provide X-Forwarded-For headers.
      // Requests arrive via the Traefik pod, which lives in the
      // cluster pod CIDR.
      loadbalancer_ips: '10.42.0.0/24',
      installation_name: 'My Zulip',
      push: {
        enabled: false,
        usage_statistics: true,
      },
      mailer: {
        enabled: false,
        host: error 'host is required',
        port: 587,
        user: error 'user is required',
      },
      oidc: {
        enabled: false,
        issuer: 'https://auth.' + _config.domain,
        client_id: 'zulip',
      },
    } + _config;
    {
      local module = self,
      local custom_settings_py = std.join('\n', [
        'SOCIAL_AUTH_OIDC_ENABLED_IDPS = ' + std.manifestPython({
          authelia: {
            oidc_url: config.oidc.issuer,
            display_name: 'Authelia',
            display_icon: 'https://www.authelia.com/svgs/branding/logo.svg',
            client_id: config.oidc.client_id,
            auto_signup: true,
          },
        }),
        'SOCIAL_AUTH_OIDC_ENABLED_IDPS["authelia"]["secret"] = get_secret("social_auth_oidc_secret")',
      ]),

      deployment: {
        apiVersion: 'apps/v1',
        kind: 'Deployment',
        metadata: {
          name: 'zulip',
        },
        spec: {
          replicas: 1,
          strategy: {
            // Zulip holds locks on the data directory and
            // PostgreSQL refuses a second instance on the same
            // volume.
            type: 'Recreate',
          },
          selector: {
            matchLabels: {
              app: 'zulip',
            },
          },
          template: {
            metadata: {
              labels: {
                app: 'zulip',
              },
              annotations: {
                // subPath config mounts do not live-update; roll the
                // pod when the RabbitMQ config changes.
                'configmap-hash': module.rabbitmqConf.config_hash,
              },
            },
            spec: {
              enableServiceLinks: false,
              // The automatic service-account token is projected at
              // /run/secrets/kubernetes.io, which collides with the zulip
              // secret volume mounted at /run/secrets, and the containers
              // have no use for API access anyway.
              automountServiceAccountToken: false,
              containers: [
                {
                  name: 'zulip',
                  image: 'ghcr.io/zulip/zulip-server:' + config.image_tag,
                  ports: [
                    {
                      containerPort: 80,
                      name: 'http',
                    },
                  ],
                  env: utils.join([
                    [
                      // TLS is terminated at Traefik.
                      { name: 'CERTIFICATES', value: '' },
                      { name: 'LOADBALANCER_IPS', value:
                        config.loadbalancer_ips },
                      // Use threaded queue workers for lower memory
                      // consumption.
                      { name: 'CONFIG_application_server__queue_workers_multiprocess', value: 'False' },
                      { name: 'CONFIG_application_server__uwsgi_processes', value: '2' },
                      // Do not aggregate rate limits across Tor exit nodes
                      // or maintain the exit-node list.
                      { name: 'SETTING_RATE_LIMIT_TOR_TOGETHER', value: 'False' },
                      { name: 'SETTING_EXTERNAL_HOST', value: 'zulip.' + config.domain },
                      { name: 'SETTING_ZULIP_ADMINISTRATOR', value: config.admin_email },
                      { name: 'SETTING_REMOTE_POSTGRES_HOST', value: 'localhost' },
                      { name: 'SETTING_RABBITMQ_HOST', value: 'localhost' },
                      { name: 'SETTING_RABBITMQ_USERNAME', value: 'zulip' },
                      { name: 'SETTING_REDIS_HOST', value: 'localhost' },
                      { name: 'SETTING_MEMCACHED_LOCATION', value: 'localhost:11211' },
                      { name: 'SETTING_MEMCACHED_USERNAME', value: 'zulip@localhost' },
                      { name: 'SETTING_ERROR_REPORTING', value: 'False' },
                    ],
                    if config.push.enabled then [
                      { name: 'SETTING_ZULIP_SERVICE_PUSH_NOTIFICATIONS', value: 'True' },
                      { name: 'SETTING_ZULIP_SERVICE_SUBMIT_USAGE_STATISTICS', value: if config.push.usage_statistics then 'True' else 'False' },
                    ],
                    if config.mailer.enabled then [
                      { name: 'SETTING_EMAIL_HOST', value: config.mailer.host },
                      { name: 'SETTING_EMAIL_PORT', value: std.toString(config.mailer.port) },
                      { name: 'SETTING_EMAIL_HOST_USER', value: config.mailer.user },
                      { name: 'SETTING_EMAIL_USE_TLS', value: 'True' },
                      { name: 'SETTING_NOREPLY_EMAIL_ADDRESS', value: 'noreply@' + std.split(config.mailer.user, '@')[1] },
                      { name: 'SETTING_TOKENIZED_NOREPLY_EMAIL_ADDRESS', value: 'noreply-{token}@' + std.split(config.mailer.user, '@')[1] },
                      { name: 'SETTING_INSTALLATION_NAME', value: config.installation_name },
                    ],
                    if config.oidc.enabled then [
                      { name: 'ZULIP_AUTH_BACKENDS', value: 'GenericOpenIdConnectBackend' },
                      {
                        name: 'ZULIP_CUSTOM_SETTINGS',
                        value: custom_settings_py,
                      },
                    ],
                  ]),
                  resources: {
                    requests: {
                      memory: '512Mi',
                    },
                    limits: {
                      memory: '1536Mi',
                    },
                  },
                  volumeMounts: [
                    {
                      name: 'data',
                      mountPath: '/data',
                    },
                    {
                      name: 'secrets',
                      mountPath: '/run/secrets',
                      readOnly: true,
                    },
                  ],
                  startupProbe: {
                    httpGet: {
                      path: '/health',
                      port: 80,
                    },
                    initialDelaySeconds: 10,
                    periodSeconds: 10,
                    timeoutSeconds: 5,
                    // First boot runs slow schema migrations.
                    failureThreshold: 60,
                  },
                  livenessProbe: {
                    httpGet: {
                      path: '/health',
                      port: 80,
                    },
                    initialDelaySeconds: 10,
                    periodSeconds: 30,
                    timeoutSeconds: 5,
                  },
                },
                {
                  name: 'postgres',
                  image: 'zulip/zulip-postgresql:14',
                  // Small-installation sizing: caps connection backends
                  // and page cache that defaults sized for a dedicated host.
                  args: [
                    'postgres',
                    '-c',
                    'max_connections=25',
                    '-c',
                    'shared_buffers=64MB',
                  ],
                  env: [
                    { name: 'POSTGRES_DB', value: 'zulip' },
                    { name: 'POSTGRES_USER', value: 'zulip' },
                    { name: 'POSTGRES_PASSWORD_FILE', value: '/run/secrets/zulip__postgres_password' },
                  ],
                  resources: {
                    requests: {
                      memory: '64Mi',
                    },
                    limits: {
                      memory: '128Mi',
                    },
                  },
                  volumeMounts: [
                    {
                      name: 'postgres-data',
                      mountPath: '/var/lib/postgresql/data',
                    },
                    {
                      name: 'secrets',
                      mountPath: '/run/secrets',
                      readOnly: true,
                    },
                  ],
                },
                {
                  name: 'memcached',
                  image: 'memcached:alpine',
                  command: [
                    'sh',
                    '-euc',
                    'echo "mech_list: plain" > "$SASL_CONF_PATH"; ' +
                    'echo "zulip@$HOSTNAME:$(cat "$MEMCACHED_PASSWORD_FILE")" > "$MEMCACHED_SASL_PWDB"; ' +
                    'echo "zulip@localhost:$(cat "$MEMCACHED_PASSWORD_FILE")" >> "$MEMCACHED_SASL_PWDB"; ' +
                    'exec memcached -S -m 32',
                  ],
                  env: [
                    { name: 'SASL_CONF_PATH', value: '/home/memcache/memcached.conf' },
                    { name: 'MEMCACHED_SASL_PWDB', value: '/home/memcache/memcached-sasl-db' },
                    { name: 'MEMCACHED_PASSWORD_FILE', value: '/run/secrets/zulip__memcached_password' },
                  ],
                  resources: {
                    requests: {
                      memory: '24Mi',
                    },
                    limits: {
                      memory: '48Mi',
                    },
                  },
                  volumeMounts: [
                    {
                      name: 'secrets',
                      mountPath: '/run/secrets',
                      readOnly: true,
                    },
                  ],
                },
                {
                  name: 'rabbitmq',
                  image: 'rabbitmq:4.2',
                  env: [
                    {
                      name: 'RABBITMQ_DEFAULT_PASS',
                      valueFrom: {
                        secretKeyRef: {
                          name: 'zulip',
                          key: 'zulip__rabbitmq_password',
                        },
                      },
                    },
                  ],
                  resources: {
                    requests: {
                      memory: '96Mi',
                    },
                    limits: {
                      memory: '192Mi',
                    },
                  },
                  volumeMounts: [
                    {
                      name: 'rabbitmq',
                      mountPath: '/var/lib/rabbitmq',
                    },
                    {
                      name: 'rabbitmq-conf',
                      mountPath: '/etc/rabbitmq/conf.d/30-zulip.conf',
                      subPath: 'rabbitmq.conf',
                    },
                  ],
                },
                {
                  name: 'redis',
                  image: 'redis:alpine',
                  args: ['--requirepass', '$(REDIS_PASSWORD)'],
                  env: [
                    {
                      name: 'REDIS_PASSWORD',
                      valueFrom: {
                        secretKeyRef: {
                          name: 'zulip',
                          key: 'zulip__redis_password',
                        },
                      },
                    },
                  ],
                  resources: {
                    requests: {
                      memory: '24Mi',
                    },
                    limits: {
                      memory: '48Mi',
                    },
                  },
                  volumeMounts: [
                    {
                      name: 'redis',
                      mountPath: '/data',
                    },
                  ],
                },
              ],
              volumes: [
                {
                  name: 'data',
                  persistentVolumeClaim: {
                    claimName: 'zulip-data',
                  },
                },
                {
                  name: 'postgres-data',
                  persistentVolumeClaim: {
                    claimName: 'zulip-postgres-data',
                  },
                },
                {
                  name: 'secrets',
                  secret: { secretName: 'zulip' },
                },
                // RabbitMQ and Redis hold only transient state.
                {
                  name: 'rabbitmq',
                  emptyDir: {},
                },
                {
                  name: 'redis',
                  emptyDir: {},
                },
                {
                  name: 'rabbitmq-conf',
                  configMap: {
                    name: module.rabbitmqConf.metadata.name,
                  },
                },
              ],
            },
          },
        },
      },

      dataPvc: {
        apiVersion: 'v1',
        kind: 'PersistentVolumeClaim',
        metadata: {
          name: 'zulip-data',
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

      postgresPvc: {
        apiVersion: 'v1',
        kind: 'PersistentVolumeClaim',
        metadata: {
          name: 'zulip-postgres-data',
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

      rabbitmqConf: utils.config_map({
        apiVersion: 'v1',
        kind: 'ConfigMap',
        metadata: {
          name: 'zulip-rabbitmq-conf',
        },
        data: {
          // RabbitMQ interpolates $(VAR) references from its environment
          // when loading config files.
          'rabbitmq.conf': 'default_user = zulip\ndefault_pass = $(RABBITMQ_DEFAULT_PASS)\n',
        },
      }),

      serviceIngress: utils.simple_service(config, { app: 'zulip', port: 80 }),
    },
}
