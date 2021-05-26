# Chess 2 Online API Server

This is a closed-source docker image which powers the API server for <https://www.chess2online.com/>. It will be of little to no use for anyone other than me.

## Installation

Store the session secret in Vault:

```bash
vault secrets enable -version=1 kv
vault policy write chess2online vault-policy.hcl
vault kv put kv/chess2online/config \
	secret=$(openssl rand -base64 32) \
```
