function(config) {
  theme: 'auto',
  server: { address: 'tcp://:9091' },
  log: { level: if config.verbose then 'debug' else 'info' },
  authentication_backend: {
    file: { path: '/var/lib/authelia/users.yml', watch: true },
  },
  access_control: {
    default_policy: 'one_factor',
  },
  session: {
    cookies: [
      {
        domain: config.domain,
        authelia_url: 'https://auth.' + config.domain,
        inactivity: '1 day',
        expiration: '1 day',
      },
    ],
  },
  storage: {
    'local': { path: '/var/lib/authelia/db.sqlite3' },
  },
  notifier: {
    filesystem: { filename: '/var/lib/authelia/notification.txt' },
  },
  identity_providers: {
    oidc: {
      clients: [
        {
          client_id: 'authelia_requires_at_least_one_client',
          public: true,
          redirect_uris: [],
        },
      ],
    },
  },
}
