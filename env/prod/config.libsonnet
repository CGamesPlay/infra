{
  local config = self,
  domain: 'cluster.cgamesplay.com',
  wildcardCertificate: true,

  workloads: {
    backup: {},
    'cert-manager': {
      email: 'ry@cgamesplay.com',
      staging: false,
      hostedZoneID: 'Z06017189PYZQUONKTV4',
    },
    core: {
      secrets: importstr 'secrets.yml',
      authelia_config: {
        access_control: {
          default_policy: 'one_factor',
          rules: [
            {
              domain: 'traefik.' + config.domain,
              policy: 'one_factor',
              subject: 'group:admins',
            },
            {
              domain: 'traefik.' + config.domain,
              policy: 'deny',
            },
          ],
        },
        identity_providers: {
          oidc: {
            clients: [
              {
                client_id: 'forgejo',
                client_name: 'Forgejo',
                client_secret: '$argon2id$v=19$m=65536,t=3,p=4$8SIHs236AJDJSCZ7Our3ag$IdeLVKaIvf4ddpAut2rYN9E+jpCCUzl3+4I6DIbXnv0',
                consent_mode: 'implicit',
                authorization_policy: 'one_factor',
                pkce_challenge_method: 'S256',
                redirect_uris: [
                  'https://code.' + config.domain + '/user/oauth2/authelia/callback',
                ],
                scopes: ['openid', 'email', 'profile', 'groups'],
              },
            ],
          },
        },
      },
    },
    chess2online: {},
    dashboard: {},
    forgejo: {
      mailer+: {
        enabled: true,
        from: '"Forgejo" <forgejo@mail.cgamesplay.com>',
        smtp_addr: 'smtp.mailgun.org',
        user: 'forgejo@mail.cgamesplay.com',
      },
    },
    seafile: {},
  },
}
