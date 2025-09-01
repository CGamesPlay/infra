# Forgejo

## Installation

Add Forgejo to the environment configuration, and enable the SSH port ingress. You can use any port in place of 2222. Add secrets.template.yml to your environment's secrets.yml in the default namespace.

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
                client_id: 'forgejo',
                client_name: 'Forgejo',
                client_secret: '$argon2id$v=19$m=65536,t=3,p=4$4xa2WF3Kja9F8MwGX/FKRg$1UuuCHv4vYX1SHd4Yma18ZOCHVjueHIQuC+63a9QO3I',
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
    forgejo: {},
  }
}
```

Once deployed, you then need to activate the OIDC client.

```bash
DOMAIN=lvh.me
CLIENT_SECRET=value-from-before
kubectl exec deployment/forgejo -- su git -- \
    forgejo admin auth add-oauth \
    --provider=openidConnect \
    --name=authelia \
    --key=forgejo \
    --secret="$CLIENT_SECRET" \
    --auto-discover-url="https://auth.$DOMAIN/.well-known/openid-configuration" \
    --scopes='openid email profile groups' \
    --group-claim-name='groups' \
    --admin-group='admins'
```

## Note for local clusters

When using `lvh.me` as the domain, you need to override the DNS and add the self-signed certificate to Forgejo in order for the auto-discover URL to work correctly. Cert-Manager MUST be enabled in order for this to work, but should be configured to use self-signed certificates.

```bash
kubectl edit configmap coredns -n kube-system
# Add this line after errors/health/ready
#   rewrite name auth.lvh.me traefik.kube-system.svc.cluster.local
# Then restart coredns
kubectl rollout restart -n kube-system deployment/coredns

# Add the self-signed certificate for the Forgejo volume
kubectl get -n admin secret/authelia-tls -o jsonpath="{.data['tls\.crt']}" | base64 -d |\
    kubectl exec -i deployments/forgejo -- tee -a /data/ssl.crt
# Update the deployment to add the CA certificate.
kubectl edit deployment/forgejo
# Add this to the env section:
# - name: SSL_CERT_FILE
#   value: /data/ssl.crt
```
