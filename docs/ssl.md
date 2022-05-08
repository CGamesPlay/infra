# SSL Runbook

### All of my SSL certificates are expired. How can I restore the system?

You should still be able to use the vault CLI using the `-tls-skip-verify`  flag or `VAULT_SKIP_VERIFY` environment variable.

**Verify that Vault is still accessible.** This should be as simple as `vault status -tls-skip-verify`.

**Rotate the vault-agent certificate.** Run the following and save the certificate to `/etc/vault-agent.d/agent.crt` and `/etc/vault-agent.d/agent.key`.

```bash
DC=nbg1
vault write -tls-skip-verify pki/issue/server-${DC} \
    common_name=server.${DC}.vault \
    ttl=24h
```

**Run the normal certificate rotation script.** Run the following.

```bash
VAULT_SKIP_VERIFY=1 /etc/cron.monthly/rotate-certificates
```

This script should rotate all of the certificates and reload the affected

### How can I renew the root certificate?

The root certificate will need to be deleted, regenerated, and distributed again to all consumers. There is no automated way to handle this process in general. The process of recreating the root certificate is:

```bash
DC=nbg1
vault secrets tune -max-lease-ttl=87600h pki
vault delete pki/root
vault write pki/root/generate/internal \
    common_name=global.vault \
    ttl=87600h
vault secrets tune -max-lease-ttl=8760h pki
vault read -tls-skip-verify -field=certificate pki/cert/ca > global.vault.crt
vault write auth/cert/certs/server-${DC} \
    name=server-${DC} \
    certificate=@global.vault.crt \
    allowed_common_names=server.${DC}.vault
```

To get the new root certificate where it's desired, you can use curl:

```bash
VAULT_ADDR=https://127.0.0.1:8200
curl -sS --insecure $VAULT_ADDR/v1/pki/ca/pem > /usr/local/share/ca-certificates/global.vault.crt
update-ca-certificates
```

As of Nomad v1.2.2, it seems to require a full service restart to detect the new CA certificate.