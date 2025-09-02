# Core Workload

This workload sets up core services: sops, traefik, and authelia.

## Authelia

Authelia is automatically set up, but can be customized with additional configuration.

### User management

To manage users, you need to edit the users yml database manually. Authelia initially creates a database with a user `authelia` / `authelia`. This can safely be removed.

```bash
POD=$(kubectl get pods -n admin -l app=authelia -o jsonpath='{.items[0].metadata.name}')
# Download the users database
kubectl cp -n admin "$POD:/var/lib/authelia/users.yml" users.yml
# Generate a password hash
kubectl exec -it -n admin "$POD" -- authelia crypto hash generate
# Upload the modified file
kubectl cp -n admin users.yml "$POD:/var/lib/authelia/users.yml"
```

### Access control

By default, any workload protected by Authelia will allow any user. To further restrict some workloads, use Authelia's [access control configuration](https://www.authelia.com/configuration/security/access-control/). The following example allows only users in the admin group to access the Traefik dashboard.

```jsonnet
{
  workloads: {
    core: {
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
      }
    }
  }
}
```

### OpenID Provider

You can configure OpenID clients by updating the environment configuration. The configuration values will vary by client capabilities, and are documented [here](https://www.authelia.com/configuration/identity-providers/openid-connect/clients/).

```jsonnet
{
  workloads: {
    core: {
      authelia_config: {
        identity_providers: {
          oidc: {
            clients: [
              // Place client configuration here.
              {
                client_id: 'my_client',
                client_name: 'My Client',
                client_secret: '$argon2id$v=19$m=65536,t=3,p=4$4xa2WF3Kja9F8MwGX/FKRg$1UuuCHv4vYX1SHd4Yma18ZOCHVjueHIQuC+63a9QO3I',
                consent_mode: 'implicit',
                authorization_policy: 'one_factor',
                pkce_challenge_method: 'S256',
                redirect_uris: [
                  'https://code.lvh.me/user/oauth2/authelia/callback',
                ],
                scopes: ['openid', 'email', 'profile', 'groups'],
              },
            ]
          }
        }
      }
    }
  }
}
```

```bash
# Generate a client secret and hash
kubectl exec -it -n admin deployments/authelia -- authelia crypto hash generate --random
```
