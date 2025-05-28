# Personal Cloud IaC

This is the repo I use for [my personal cloud server](https://cgamesplay.com/post/2021/10/27/creating-my-personal-cloud-with-hashicorp/), hosted as a VPS.

**Features:**

- Single-node [K3s](https://k3s.io) installation.
- Encryption at rest for Kubernetes secrets, etcd, and all container persistent volumes.
- Atomic upgrades by storing all stateful data on an external volume.
- Local development environment via [Lima](https://lima-vm.io)
- Production deployment via [Hetzner](https://www.hetzner.com).
  - Automatic SSL certificates via [LetsEncrypt](https://letsencrypt.org).

- A [variety of workloads](./terraform) that I've deployed. Some highlights:
  - [backup](./terraform/backup) - back up the system using [Restic](https://restic.net) on a periodic basis.
  - [registry](./nomad/registry) - host a private [Docker](https://www.docker.com/) registry, which can be referenced by other Nomad jobs.
  - See the full list [here](./terraform).

## System components

**Terraform**

[Terraform](https://www.terraform.io) is used to describe the very simple infrastructure requirements for the cluster. This is primarily intended to be a base for future improvements, if the cluster ever needs to move to a multi-node setup.

**SOPS**

[Mozilla SOPS](https://getsops.io/docs/) is used to encrypt Kubernetes secrets in this repository, and combined with [sops-secrets-operator](https://github.com/isindir/sops-secrets-operator/) to decrypt them on the cluster.

## Installation

1. Configure your environment. The requirements:
   - `HCLOUD_TOKEN` is the Hetzner Cloud token.
   - `ssh-add -L` needs to show at least one key (it will be used as the key for the created instances).
   - `python --version` needs to be 3. `apt install python-is-python3` on Ubuntu.
   - `pip3 install ansible hvac ansible-modules-hashivault`
2. Run `argc infra apply` to sync the infrastructure. This command requires confirmation before continuing, but you can also use `plan` or any other Terraform arguments.
3. Run `argc ansible` to apply the configuration. The change detection does not work correctly on the first run, so `-CD` cannot be used here. They will work after a run has completed at least once.
   - The Vault creation will drop `vault.txt` in the repository root, which contains the Vault unseal keys and root token. Store these safely and delete the file.
   - Optionally, `argc verify` can be used to diagnose some basic issues now and in the future.
4. Connect to the machine using ssh (use `argc master_ip` for the IP address) and follow the [WireGuard docs](./docs/wireguard.md) to set up the initial peer.
5. Deploy jobs with Nomad. Use `argc nomad apply`.
   - This will apply the terraform workspace in the `nomad` directory.

### Local environment setup

To access the cluster from your local machine:

1. Install the generated CA at `bootstrap/data/ca.crt` to configure SSL. You can install it using Keychain Access.app into the login keychain, but you will need to manually trust the certificate, which is done from the certificate info window under "Trust".
  - This also enables UI access in the browser: [Consul](https://172.30.0.1:8501/) | [Vault](https://172.30.0.1:8200/) | [Nomad](https://172.30.0.1:4646/)
2. Configure WireGuard and connect it.
3. Set up local DNS to use Consul.
4. Use `eval $(argc env)` to get the necessary environment variables.

### Accessing Consul DNS over Wireguard

The generated WireGuard configuration does not specify DNS servers for the tunnel. If you want to resolve `service.consul` addresses through the tunnel, you need to either route all DNS through the tunnel, or configure your machine to only route the desired queries through the tunnel.

**macOS**

You can configure your macOS system DNS to use the tunnel for the `.consul` TLD only using this snippet. [This StackExchange answer](https://apple.stackexchange.com/a/385218/14873) has more information and debugging tips.

```bash
sudo scutil <<EOF
d.init
d.add ServerAddresses * 172.30.0.1
d.add SupplementalMatchDomains * consul
set State:/Network/Service/Consul/DNS
EOF
```

Note that even if you do this, programs written in go (like Nomad, Consul, and Vault) [will not respect this setting](https://github.com/golang/go/issues/12524), so you will need to specify IP addresses when using these CLIs. Additionally, this command needs to be run on every boot (see [an example of automating this configuration](https://github.com/CGamesPlay/dotfiles/blob/master/macos/Library/LaunchAgents/local.dns.cluster.plist)). This is resolved in Go 1.20, released 2023-02-01.

**iOS**

WireGuard for iOS always routes all DNS through the tunnel. Traffic is not routed through the tunnel, only DNS.

If everything works, you should be able to SSH to nodes using their names:

```bash
ssh server-master.node.consul
```

## Terraform modules

The terraform directory contains a variety of modules used to control the Kubernetes cluster. The terraform state is also stored in the cluster.

- `lima/` is the root module for local development.
- `terraform/` is the main module, defining the providers and backend.
  - `admin/` is the base module which should always be included. It includes Traefik and Authelia.

## Using Nomad

Now that the server is set up, you'll want to start running some jobs on your new cluster. Your first two jobs should be [traefik](./nomad/traefik) and [whoami](./nomad/whoami.disabled), which will allow you to verify that everything is working properly. After that, you can do whatever you like. My [nomad directory](./nomad) has the jobspecs that I am using, which you can use as a baseline for your own.

This repository uses Terraform to configure the jobs. Each directory in `nomad` has a `main.tf` which is includes from the main `nomad/main.tf`. Use `argc nomad --help` to see how to deploy Nomad jobs using the system.

### Note about storage

Presently, all of my stateful workloads reside on the master node. As a result, I haven't invested in any container storage interfaces, and I use plain Docker bind mounts to attach stateful volumes. If you want to do this, you'll need to enable the feature in `/etc/nomad.d/client.hcl`:

```hcl
plugin "docker" {
  config {
    volumes {
      enabled = true
    }
  }
}
```

### Deploying from CI/CD

The Ansible playbooks set up an AppRole auth method preconfigured with a deployment role. Basically, you can use a script like the following to get a Nomad token which is able to submit jobs and scale them (but is otherwise limited).

1. Install the [gitlab-ci.yml template](script/Deploy.gitlab-ci.yml) to the repository you want to deploy. Note that the deploy image referenced is specific to my cluster, you'll want to generate your own with your CA cert installed.
2. Find the correct RoleID and the value in the template: `vault read auth/approle/role/deploy/role-id`
3. Create a new SecretID using `vault write -f auth/approle/role/deploy/secret-id`. Save this as `VAULT_SECRET_ID` in the CI/CDs secrets store.

If you want a more manual approach, these curl snippets will get the token without installing the Vault CLI.

```bash
VAULT_ADDR=https://myvault.example.tld # Fill in appropriately.
VAULT_ROLE_ID=2d68a8af-e06f-7746-4bf2-4dc55d07108a # From Step 2
# Make sure to install the CA certificate.

VAULT_TOKEN=$(curl --request POST --data '{ "role_id": "'$VAULT_ROLE_ID'", "secret_id": "'$VAULT_SECRET_ID'" }' $VAULT_ADDR/v1/auth/approle/login \
	| jq -r ".auth.client_token") || exit $?
NOMAD_TOKEN=$(curl --header "X-Vault-Token: $VAULT_TOKEN" $VAULT_ADDR/v1/nomad/creds/deploy \
	| jq -r '.data.secret_id') || exit $?
```

## Networking reference

| CIDR           | Purpose                                                      |
| -------------- | ------------------------------------------------------------ |
| 172.17.0.0/16  | Internal addresses for Docker containers.                    |
| 172.30.0.0/16  | Wireguard addresses. This is the main way in which nodes communicate with each other. |
| 172.30.252.0/22  | Roaming peer subnet. |
| 172.30.0.0/22  | Peers located in nbg1. |
| 172.31.0.0/16  | Physical IP address of nodes. The particular arrangement of this subnet depends on the datacenter. |

Set up security groups such that the machines in the cluster can only communicate with each other over Wireguard (51820 UDP). Incoming connections will only go to the traefik machine.

For reference, here are the ports used by the main programs: Nomad (4646-4647 plus 20000-32000 for services), Consul (8300-8302, 8500), Vault (8200-8201).

## Security Model

This is a toy project for personal use. As a result, the security model has been simplified from the normal one that you would encounter in a production system. At its core, the key difference is that a single-node system will be fully compromised if root access is gained on that node. The key implication of this is: **if a job escapes its sandbox, everything is compromised.** Specifically:

- Access to the root privileges on the host system can be used to read secrets directly out of Vault's memory.
- Access to the Docker socket on the host system can be used to run an arbitrary container with root privileges on the host system.
- Access to Nomad can be used to submit an arbitrary job with root privileges on the host system.

As a result of these serious limitations, some aspects of the original security model have been superseded and are not necessary:

- The Nomad server can also act as a Nomad client (a compromised client already implies the entire cluster is compromised)
- Vault can store its configuration in the same Consul cluster as Nomad (a compromised Nomad client already implies the entire cluster is compromised).

The steps required to make this setup "production-ready" are:

1. Make a Vault cluster of at least 3 nodes, and using a Consul cluster disconnected from the production one, and with more than a single unseal key.
2. Make a Nomad server cluster of at least 3 nodes, which do not run the Nomad client.
3. Set up some sort of container storage interface or or networked filesystem to use with the Nomad clients.

## Changes

- The infrastructure underwent a substantial change from Nomad to Kubernetes. The older version can be found [here](https://github.com/CGamesPlay/infra/commit/35120ca5e04795cad60536bc5f91c0c6f89f4d15).
