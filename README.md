# Personal Cloud IaC

This is the repo I use for my personal cloud server, hosted as a VPS. At the time of writing this document, the system is a single node, therefore the security model is somewhat simpler than a production system and no container storage interfaces need to be configured.

**Features:**

- Single-node [Nomad](https://www.nomadproject.io), [Consul](https://www.consul.io), and [Vault](https://www.vaultproject.io) installation.
- mTLS configured between all services.
- [WireGuard](https://www.wireguard.com) used to secure communication between nodes (theoretically, since there's only one node).
- Access to GUI management portals via WireGuard (presently, the real use of WireGuard).
- A [variety of Nomad jobs](./nomad) that I've developed. Some highlights:
  - [backup](./nomad/backup) - back up the system to S3 using [Restic](https://restic.net) on a periodic basis.
  - [registry](./nomad/registry) - host a private [Docker](https://www.docker.com/) registry, which can be referenced by other Nomad jobs.
  - [traefik](./nomad/traefik) - expose Nomad jobs to the internet using [Traefik](https://traefik.io/traefik/) and [LetsEncrypt](https://letsencrypt.org).
  - See the full list [here](./nomad).

## System components

**Terraform**

[Terraform](https://www.terraform.io) is used to describe the very simple infrastructure requirements for the cluster. This is primarily intended to be a base for future improvements, if the cluster ever needs to move to a multi-node setup.

**Nomad**

The master node runs the Nomad server, and all other nodes run Nomad clients. Nomad is responsible for running Traefik and all of the actual workloads. Nomad needs a way to know which machines are Nomad clients, and what workloads they are running, for which it uses Consul.

**Consul**

Consul is used to store configuration and state information about the cluster. Each Nomad workload will register as a service in Consul, which in turn can be used to resolve the IP addresses and port information to reach those services from anywhere in the cluster.

**Vault**

Vault is used to store secrets and issue internal TLS certificates. It is not directly required by Nomad, but Nomad does have a tight Vault integration to allow workloads to securely receive secrets. Vault stores its data in Consul (:warning: in a real production system we would want to use a separate Consul cluster specifically to store Vault data).

**WireGuard**

WireGuard is used to secure communications between cluster nodes. This allows us to securely keep a private network even between multiple regions and cloud providers.

## Installation

1. Use `bootstrap/prepare.sh` to create a local Consul and Vault instance that is pre-bootstrapped. This design allows you to experiment locally with the applications while preparing to bootstrap.
2. Use `terraform apply` in the `infra` directory to create the infrastructure.
3. Use `bootstrap/generate_installer.sh` to generate a bash script. You can either manually enter these commands onto your server, or use a script like `bootstrap/generate_installer.sh | ssh MY_IP -- sudo bash`.
4. Set up your local environment using the access tokens from `bootstrap/data`, and securely delete the folder afterwards. Take special care to store the Vault unlock key someplace secure!
5. Set up your local environment with the necessary credentials.
6. Begin using Nomad in your new cluster. Note: you will need to run `nomad acl bootstrap` to create your initial root token; the prepare script does not create one for you.

### Local environment setup

To access the cluster from your local machine:

- Use the generated Wireguard config file at `bootstrap/data/wg0.conf` to connect to the datacenter.
- Install the generated CA at `bootstrap/data/ca.crt` to configure SSL. You can install it using Keychain Access.app into the login keychain, but you will need to manually trust the certificate, which is done from the certificate info window under "Trust".
  - This also enables UI access in the browser: [Consul](https://172.30.0.1:8501/) | [Vault](https://172.30.0.1:8200/) | [Nomad](https://172.30.0.1:4646/)

The CLI tools require environment variables to be configured as well:

```bash
export VAULT_ADDR=https://172.30.0.1:8200
export NOMAD_ADDR=https://172.30.0.1:4646
export CONSUL_HTTP_ADDR=https://172.30.0.1:8501
export NOMAD_TOKEN=...
export CONSUL_HTTP_TOKEN=...
export VAULT_TOKEN=...
```

You can find initial root tokens for Consul in `bootstrap/data/consul-acl.txt` and for Vault in `bootstrap/data/vault-root-keys.txt`.

### Accessing Consul DNS over Wireguard on macOS

The generated WireGuard configuration does not specify DNS servers for the tunnel. If you want to resolve `service.consul` addresses through the tunnel, you need to either route all DNS through the tunnel, or configure your machine to only route the desired queries through the tunnel.

**macOS**

You can configure your macOS system DNS to use the tunnel for the `service.consul` domain only using this snippet. [This StackExchange answer](https://apple.stackexchange.com/a/385218/14873) has more information and debugging tips.

```bash
sudo scutil <<EOF
d.init
d.add ServerAddresses * 172.30.0.1
d.add SupplementalMatchDomains * consul
set State:/Network/Service/Consul/DNS
EOF
```

Note that even if you do this, programs written in go (like Nomad, Consul, and Vault) [will not respect this setting](https://github.com/golang/go/issues/12524), so you will need to specify IP addresses when using these CLIs. Additionally, this command needs to be run on every boot.

**iOS**

WireGuard for iOS always routes all DNS through the tunnel. Traffic is not routed through the tunnel, only DNS.

If everything works, you should be able to SSH to nodes using their names:

```bash
ssh server-master.node.consul
```

## Using Nomad

Now that the server is set up, you'll want to start running some jobs on your new cluster. Your first two jobs should be [traefik](./nomad/traefik) and [whoami](./nomad/whoami.disabled), which will allow you to verify that everything is working properly. After that, you can do whatever you like. My [nomad directory](./nomad) has the jobspecs that I am using, which you can use as a baseline for your own.

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

## Networking reference

| CIDR           | Purpose                                                      |
| -------------- | ------------------------------------------------------------ |
| 172.17.0.0/16  | Internal addresses for Docker containers.                    |
| 172.30.0.0/16  | Wireguard addresses. This is the main way in which nodes communicate with each other. |
| 172.30.0.0/20  | Wireguard subnet for nbg1.                                   |
| 172.30.15.0/24 | Reserved for incoming links to nbg1.                         |
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
