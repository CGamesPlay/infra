# Private Docker Registry

The private Docker registry provides a convenient way to host private images which will run on the cluster.

## Installation

Authentication on the registry is configured through the `htpasswd` mechanism.

>  Presently, the file is statically configured on the developer machine (I only use a single user for the entire registry, so this is sufficient for me). This information could alternatively be stored in Vault.

Create the `htpasswd` file locally:

```bash
username=my_username
password=$(openssl rand -base64 32)
docker run --rm --entrypoint htpasswd httpd:2 -Bbn $username $password > htpasswd
```

Then deploy the job using levant. You should be able to use `docker login` to access the new registry (which will be on the "registry" subdomain) after a few seconds.

```bash
docker login registry.$base_domain -u $username -p $password
```

### Optional: Configure Nomad

You need to configure Nomad to be able to download private images. You can do this through the typical way: setting the `auth` stanza in the job file, but you can also configure the authentication globally so all Nomad jobs can use it without additional configuration. Steps:

1. Manually run `docker login` on each client node as the root account, so that the authentication info is cached in `/root/.docker/config.json`.
2. Merge the following config into the `client.hcl` on each client node.
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
