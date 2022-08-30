# Private Docker Registry

The private Docker registry provides a convenient way to host private images which will run on the cluster.

## Installation

Authentication on the registry is configured through the `htpasswd` mechanism. The password file is stored in Vault. To create a suitable file, run a script like this one:

```bash
username=my_username
password=$(openssl rand -base64 32)
password_hash=$(python3 -c 'import bcrypt; print(bcrypt.hashpw("'$password'".encode("utf-8"), bcrypt.gensalt()).decode("utf-8"))')
vault secrets enable -version=1 kv
vault kv put kv/docker/users htpasswd="$username:$password_hash"
```

Then deploy the job using levant. You should be able to use `docker login` to access the new registry (which will be on the "registry" subdomain) after a few seconds.

```bash
docker login registry.$base_domain -u $username -p $password
```

### Optional: Configure Nomad

You need to configure Nomad to be able to download private images. You can do this through the typical way: setting the `auth` stanza in the job file, but you can also configure the authentication globally so all Nomad jobs can use it without additional configuration. Steps:

1. Manually run `docker login` on each client node as the root account, so that the authentication info is cached in `/root/.docker/config.json`.
2. Merge the following config into the `/etc/nomad.d/client.hcl` on each client node.
3. Restart the Nomad clients.

```hcl
plugin "docker" {
  config {
    auth {
      config = "/root/.docker/config.json"
    }
  }
}
```
