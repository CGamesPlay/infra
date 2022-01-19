# Launa

This is the Nomad job which powers my Launa instance.

## Installation

Store the session secret in Vault:

```bash
vault secrets enable -version=1 kv
vault policy write launa vault-policy.hcl
vault kv put kv/launa/config \
    nextauthSecret=$(openssl rand -base64 32) \
    googleClientId=$GOOGLE_CLIENT_ID \
    googleClientSecret=$GOOGLE_CLIENT_SECRET \
    openweatherKey=$OPENWEATHER_KEY
```
