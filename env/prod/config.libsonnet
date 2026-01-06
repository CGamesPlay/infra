{
  local config = self,
  domain: 'cluster.cgamesplay.com',
  wildcardCertificate: true,
  tcp_ports: { ssh: 2222 },

  workloads: {
    backup: {},
    'cert-manager': {
      email: 'ry@cgamesplay.com',
      staging: false,
      hostedZoneID: 'Z06017189PYZQUONKTV4',
    },
    core: {
      secrets: importstr 'secrets.yml',
      mailer+: {
        enabled: true,
        sender: 'Authelia <authelia@mail.cgamesplay.com>',
        address: 'submission://smtp.mailgun.org:587',
        username: 'forgejo@mail.cgamesplay.com',
      },
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
              {
                client_id: 'romm',
                client_name: 'RomM',
                client_secret: '$argon2id$v=19$m=65536,t=3,p=4$UyhbhLOY3A1ewbVo+W1v+w$8gstH/JMx9QKvK0H0Xub7sufjZDouXl8CJu6eGsm58s',
                consent_mode: 'implicit',
                authorization_policy: 'one_factor',
                redirect_uris: [
                  'https://romm.' + config.domain + '/api/oauth/openid',
                ],
                scopes: ['openid', 'email', 'profile'],
                claims_policy: 'romm',
              },
            ],
            claims_policies: {
              // https://github.com/rommapp/romm/issues/1927
              romm: {
                id_token: ['email', 'email_verified', 'alt_emails', 'preferred_username', 'name'],
              },
            },
          },
        },
      },
    },
    chess2online: {},
    dashboard: {},
    forgejo: {
      image_tag: '13.0.3',
      mailer+: {
        enabled: true,
        from: '"Forgejo" <forgejo@mail.cgamesplay.com>',
        smtp_addr: 'smtp.mailgun.org',
        user: 'forgejo@mail.cgamesplay.com',
      },
    },
    romm: {
      sso: true,
    },
    seafile: {},
  },
}
