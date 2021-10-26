# Chess 2 Online API Server

This is a closed-source docker image which powers the API server for <https://www.chess2online.com/>. It cannot be run by anyone other than me, however it does show a few useful techniques:

- Running a container hosted on the hosted private Docker registry.
- Configuring custom Traefik rules on a job.
- Storing ad-hoc secret data in Vault.

## Installation

Store the session secret in Vault:

```bash
vault secrets enable -version=1 kv
vault policy write chess2online vault-policy.hcl
vault kv put kv/chess2online/config \
	secret=$(openssl rand -base64 32) \
```
