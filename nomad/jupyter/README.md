# Jupyter Lab

This provides a [Jupyter](https://jupyter.org) environment, configured for a single user.

## Installation

Create an empty configuration in Vault:

```bash
vault secrets enable -version=1 kv
vault policy write jupyter vault-policy.hcl
vault kv put kv/jupyter/config password_hash=""
```

Start the job. You could extract the token from the allocation logs, but to set a password, log into the instance:

```bash
nomad alloc exec -i -t -task server $ALLOCATION_ID /bin/bash
jupyter server password --config=$(pwd)/temp.json
cat temp.json
exit
```

Copy the entire "password" value and assign it to the previously-created Vault key:

```bash
# Make sure to use single quotes to properly escape the string
PASSWORD_HASH='argon2:$argon2id$v=19$m=10240,t=10,p=8$C+Srb6yq+TBQL6CcjaAehA$SylbTqzEA6HKc5vE4UpXmDGwyEYsyLlv6jDkcOsaw+4'
vault kv put kv/jupyter/config password_hash=$PASSWORD_HASH
```

Finally, stop the old jupyter job and deploy again to update the template with the password.