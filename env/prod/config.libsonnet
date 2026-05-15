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
            lifespans: {
              custom: {
                offline_access: {
                  // Should ideally use shorter-lived access tokens to enable
                  // more rapid revocation, but...
                  // https://github.com/coder/coder/issues/25275
                  access_token: '8h',
                  refresh_token: '7d',
                },
              },
            },
            clients: [
              {
                client_id: 'headscale',
                client_name: 'Headscale',
                client_secret: '$argon2id$v=19$m=65536,t=3,p=4$ZUQXpaIuUKJjE/KNJug2Kg$rA+sV4PR7KNRuPoF9M/4GH6zoIwahVMdv1TJeczcjmY',
                consent_mode: 'implicit',
                authorization_policy: 'one_factor',
                pkce_challenge_method: 'S256',
                redirect_uris: [
                  'https://headscale.' + config.domain + '/oidc/callback',
                ],
                scopes: ['openid', 'email', 'profile', 'groups'],
              },
              {
                client_id: 'forgejo',
                client_name: 'Forgejo',
                client_secret: '$argon2id$v=19$m=65536,t=3,p=4$8SIHs236AJDJSCZ7Our3ag$IdeLVKaIvf4ddpAut2rYN9E+jpCCUzl3+4I6DIbXnv0',
                consent_mode: 'implicit',
                authorization_policy: 'one_factor',
                pkce_challenge_method: 'S256',
                redirect_uris: [
                  'https://f.200-ok.link/user/oauth2/authelia/callback',
                ],
                scopes: ['openid', 'email', 'profile', 'groups'],
              },
              {
                client_id: 'coder',
                client_name: 'Coder',
                client_secret: '$argon2id$v=19$m=65536,t=3,p=4$O6mf9Pbvg43HWOhzJ41/MQ$Y7JfyK2opQ8R30uuasM1RUKisHHHm2Zj6/Qb8ywAagY',
                consent_mode: 'implicit',
                authorization_policy: 'one_factor',
                redirect_uris: ['https://c.200-ok.link/api/v2/users/oidc/callback'],
                scopes: ['openid', 'profile', 'email', 'groups', 'offline_access'],
                grant_types: ['authorization_code', 'refresh_token'],
                response_types: ['code'],
                lifespan: 'offline_access',
                token_endpoint_auth_method: 'client_secret_post',
              },
              {
                client_id: 'romm',
                client_name: 'RomM',
                client_secret: '$argon2id$v=19$m=65536,t=3,p=4$UyhbhLOY3A1ewbVo+W1v+w$8gstH/JMx9QKvK0H0Xub7sufjZDouXl8CJu6eGsm58s',
                consent_mode: 'implicit',
                authorization_policy: 'one_factor',
                redirect_uris: [
                  'http://raspi.ts.200-ok.link:1996/api/oauth/openid',
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
    headscale: {},
    seafile: {},
  },
}
