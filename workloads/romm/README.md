# RomM

A beautiful, powerful, self-hosted rom manager and player. [Website](https://romm.app/)

## Installation

Add Romm to the environment configuration. Add secrets.template.yml to your environment's secrets.yml in the default namespace.

```bash
# Generate a client secret and hash it.
kubectl exec -it -n admin deployment/authelia -- authelia crypto hash generate --random
```

```jsonnet
// Environment config
{
  local config = self,
  domain: 'lvh.me',
  // Optional.
  tcp_ports: { ssh: 2222 },
  workloads: {
    core: {
      authelia_config: {
        identity_providers: {
          oidc: {
            clients: [
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
    romm: {},
  }
}
```

When you open the app for the first time, it will put you into the new-user experience. Create a new user which matches the email address of your authelia user (username and password don't matter). After compelting the new-user experience, you will be directed to the SSO login.
