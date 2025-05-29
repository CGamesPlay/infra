# Personal Cloud IaC

This is the repo I use for [my personal cloud server](https://cgamesplay.com/post/2021/10/27/creating-my-personal-cloud-with-hashicorp/), hosted as a VPS.

**Features:**

- Single-node [K3s](https://k3s.io) installation.
- Encryption at rest for Kubernetes secrets, etcd, and all container persistent volumes.
- Atomic upgrades by storing all stateful data on an external volume.
- Easily create local environments for testing.
- Automatic SSL certificates via [LetsEncrypt](https://letsencrypt.org).

- A [variety of workloads](./workloads) that I've deployed. Some highlights:
  - [backup](./workloads/backup) - back up the system using [Restic](https://restic.net) on a periodic basis.
  - [registry](./nomad/registry) - host a private [Docker](https://www.docker.com/) registry, which can be referenced by other Nomad jobs.
  - See the full list [here](./workloads).

## System components

**K3s**

[K3s](https://k3s.io) is a lightweight Kubernetes distribution which includes useful single-node-cluster features like host path volumes, a LoadBalancer, and [Traefik](https://traefik.io/traefik/).

**Terraform**

[Terraform](https://www.terraform.io) is used to declare the desired Kubernetes workloads. The state is itself stored in the Kubernetes cluster.

**SOPS**

[Mozilla SOPS](https://getsops.io/docs/) is used to encrypt Kubernetes secrets in this repository, and combined with [sops-secrets-operator](https://github.com/isindir/sops-secrets-operator/) to decrypt them on the cluster. We use [Age](https://age-encryption.org/) to as the encryption provider.

## Installation

### 1. Choose Technology

Choose the technology you will deploy to:

- [Lima](https://lima-vm.io) is available for quickly spinning up test clusters on a local macOS machine.
- [Hetzner Cloud](https://www.hetzner.com) is available for creating a cloud-hosted cluster.

### 2. Configure Dependencies

The Lima driver requires that `limactl` is installed.

The Hetzner driver requires that `hcloud` is installed. For Hetzner, your should also create an empty project to host the resources you will use. Set up `hcloud` using `hcloud context` or by setting `HCLOUD_TOKEN`.

Generate an age key if you don't already have one: `age-keygen -o development.key`. The public key will be printed to the console; it should look like `age1qal59j7k2hphhmnmurg4ymj9n32sz5dgnx5teks3ch72n4wjfevsupgahc`.

### 3. Initialize Cluster

Run `argc init --driver=lima --age $AGE_PUBLIC_KEY local` to create a cluster named `local` using the Lima driver. `$AGE_PUBLIC_KEY` should be your age public key. This command should take a few minutes to run and should stream logs throughout the process.

At the end, the script will print the disk encryption password. It is important that you store this somewhere safe; it is necessary to reboot or upgrade the server.

To use the Hetzner driver, run `argc init --help` and `argc init --driver=hetzner --driver-help` to see the arguments you need to pass. At a minimum, you'll need to use `--location`, `--type`, and `--size`.

You can create any number of clusters. Each stores its configuration in a subdirectory of `env/`. Looking at the local cluster in `env/local/`, we see these files:

- `kubeconfig.yml` is the kubeconfig you can use to access the cluster.
- `main.tf` is the root terraform module used to deploy workloads to the cluster.
- `admin-secrets.yml` contains the secrets necessary to get the core services working (Authelia). They are randomly generated.
- `authelia-users.yml` contains a sample Authelia users database.
- `sops-age-recipient.txt` is the public key of the cluster's sops-secret-operator.

### 4. Use Cluster

The default cluster configuration is an empty k3s installation. Use `argc sync` to deploy the workloads from `main.tf` to the cluster.

- [Dashboard](https://lvh.me/) - accessible via the self-signed certificate. Log in with authelia / authelia.
- `kubectl` - Use `env/local/kubeconfig.yml` to access
- `argc sync local` - Run this to sync modifications to `env/local/main.tf`.

### 5. Upgrade The Server

We treat the server as immutable.

### 6. Clean Up

Once you no longer need an environment, use `argc destroy` to remove it. This will delete all local/cloud resources, and remove the `env/` subdirectory.

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

- The infrastructure underwent a substantial change from Nomad to Kubernetes. The older version can be found [here](https://github.com/CGamesPlay/infra/commit/35120ca5e04795cad60536bc5f91c0c6f89f4d15). It uses Nomad, Consul, and Vault, as well as Ansible for managing the configuration of the server.
