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
      image_tag: '12',
      // Use mailer+: { enabled: true, ... } to enable, and set the
      // mailer_passwd secret.
      mailer: {
        enabled: false,
        from: '"Forgejo" <forgejo@%s>' % _config.domain,
        smtp_protocol: '',
        smtp_addr: error 'smtp_addr is required',
        smtp_port: 587,
        user: error 'user is required',
      },
    } + _config;
    {
      local module = self,

      deployment: {
        apiVersion: 'apps/v1',
        kind: 'Deployment',
        metadata: {
          name: 'forgejo',
        },
        spec: {
          replicas: 1,
          selector: {
            matchLabels: {
              app: 'forgejo',
            },
          },
          template: {
            metadata: {
              labels: {
                app: 'forgejo',
              },
            },
            spec: {
              enableServiceLinks: false,
              containers: [
                {
                  name: 'forgejo',
                  image: 'codeberg.org/forgejo/forgejo:' + config.image_tag,
                  ports: [
                    { containerPort: 3000 },
                    { containerPort: 22 },
                  ],
                  volumeMounts: [
                    { name: 'secrets', mountPath: '/etc/gitea' },
                    { name: 'data', mountPath: '/data' },
                  ],
                  env: [
                    { name: 'FORGEJO____APP_NAME', value: 'Forgejo' },
                    { name: 'FORGEJO__admin__SEND_NOTIFICATION_EMAIL_ON_NEW_USER', value: 'true' },
                    { name: 'FORGEJO__cron__ENABLED', value: 'true' },
                    { name: 'FORGEJO__indexer__REPO_INDEXER_ENABLED', value: 'true' },
                    { name: 'FORGEJO__mailer__ENABLED', value: std.toString(config.mailer.enabled) },
                    { name: 'FORGEJO__oauth2_client__ACCOUNT_LINKING', value: 'auto' },
                    { name: 'FORGEJO__oauth2_client__ENABLE_AUTO_REGISTRATION', value: 'true' },
                    { name: 'FORGEJO__oauth2_client__UPDATE_AVATAR', value: 'true' },
                    { name: 'FORGEJO__openid__WHITELISTED_URIS', value: 'auth.' + config.domain },
                    { name: 'FORGEJO__repository__ENABLE_PUSH_CREATE_ORG', value: 'true' },
                    { name: 'FORGEJO__repository__ENABLE_PUSH_CREATE_USER', value: 'true' },
                    { name: 'FORGEJO__security__INSTALL_LOCK', value: 'true' },
                    { name: 'FORGEJO__security__SECRET_KEY__FILE', value: '/etc/gitea/secret_key' },
                    { name: 'FORGEJO__server__DOMAIN', value: 'code.' + config.domain },
                    { name: 'FORGEJO__server__LANDING_PAGE', value: '/user/oauth2/authelia' },
                    { name: 'FORGEJO__server__LFS_START_SERVER', value: 'true' },
                    { name: 'FORGEJO__server__ROOT_URL', value: 'https://code.' + config.domain + '/' },
                    { name: 'FORGEJO__server__SSH_DOMAIN', value: '%(DOMAIN)s' },
                    { name: 'FORGEJO__service__ALLOW_ONLY_EXTERNAL_REGISTRATION', value: 'true' },
                    { name: 'FORGEJO__service__ENABLE_INTERNAL_SIGNIN', value: 'false' },
                    { name: 'FORGEJO__service__ENABLE_NOTIFY_MAIL', value: 'true' },
                    { name: 'FORGEJO__service__REQUIRE_SIGNIN_VIEW', value: 'true' },
                    { name: 'FORGEJO__service__SHOW_REGISTRATION_BUTTON', value: 'false' },
                    { name: 'FORGEJO__session__PROVIDER', value: 'db' },
                  ] + (if std.objectHas(config.tcp_ports, 'ssh') then [
                         { name: 'FORGEJO__server__SSH_PORT', value: std.toString(config.tcp_ports.ssh) },
                       ] else [
                         { name: 'FORGEJO__server__DISABLE_SSH', value: 'true' },
                       ]) + if config.mailer.enabled then [
                    { name: 'FORGEJO__mailer__FROM', value: config.mailer.from },
                    { name: 'FORGEJO__mailer__PROTOCOL', value: config.mailer.smtp_protocol },
                    { name: 'FORGEJO__mailer__SMTP_ADDR', value: config.mailer.smtp_addr },
                    { name: 'FORGEJO__mailer__SMTP_PORT', value: std.toString(config.mailer.smtp_port) },
                    { name: 'FORGEJO__mailer__USER', value: config.mailer.user },
                    { name: 'FORGEJO__mailer__PASSWD__FILE', value: '/etc/gitea/mailer_passwd' },
                  ],
                  resources: {
                    requests: {
                      memory: '512Mi',
                    },
                    limits: {
                      memory: '1Gi',
                    },
                  },
                  livenessProbe: {
                    httpGet: {
                      path: '/api/healthz',
                      port: 3000,
                    },
                    initialDelaySeconds: 30,
                    periodSeconds: 30,
                    timeoutSeconds: 10,
                  },
                },
              ],
              volumes: [
                {
                  name: 'secrets',
                  secret: { secretName: 'forgejo' },
                },
                {
                  name: 'data',
                  persistentVolumeClaim: { claimName: 'forgejo-data' },
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
          name: 'forgejo-data',
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

      service: {
        apiVersion: 'v1',
        kind: 'Service',
        metadata: { name: 'forgejo' },
        spec: {
          selector: {
            app: 'forgejo',
          },
          ports: [
            { name: 'http', port: 3000 },
          ] + if std.objectHas(config.tcp_ports, 'ssh') then [
            { name: 'ssh', port: 22 },
          ] else [],
        },
      },

      ingress: utils.traefik_ingress(config, {
        app: 'forgejo',
        port: 3000,
        host: 'code.' + config.domain,
        middlewares: [core.auth_middleware],
      }),

      [if std.objectHas(config.tcp_ports, 'ssh') then 'sshIngress']: {
        apiVersion: 'traefik.io/v1alpha1',
        kind: 'IngressRouteTCP',
        metadata: {
          name: 'forgejo-ssh',
        },
        spec: {
          entryPoints: ['ssh'],
          routes: [{
            match: 'HostSNI(`*`)',
            services: [{
              name: 'forgejo',
              port: 'ssh',
            }],
          }],
        },
      },
    },
}
