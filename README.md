# Personal Cloud IaC

This is the repo I use for [my personal cloud server](https://cgamesplay.com/post/2021/10/27/creating-my-personal-cloud-with-hashicorp/), hosted as a VPS. At the time of writing this document, the system is a single node, therefore the security model is somewhat simpler than a production system and no container storage interfaces need to be configured.

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

**Ansible**

[Ansible](https://www.ansible.com) is used to update all configuration files on all nodes. This includes the configuration for Vault, Vault Agent, Consul, Nomad, and WireGuard.

**Nomad**

The master node runs the Nomad server, and all other nodes run Nomad clients. Nomad is responsible for running Traefik and all of the actual workloads. Nomad needs a way to know which machines are Nomad clients, and what workloads they are running, for which it uses Consul.

**Consul**

Consul is used to store configuration and state information about the cluster. Each Nomad workload will register as a service in Consul, which in turn can be used to resolve the IP addresses and port information to reach those services from anywhere in the cluster.

**Vault**

Vault is used to store secrets and issue internal TLS certificates. It is not directly required by Nomad, but Nomad does have a tight Vault integration to allow workloads to securely receive secrets. Vault stores its data in Consul (:warning: in a real production system we would want to use a separate Consul cluster specifically to store Vault data). Vault Agent is a component of Vault which is used to update configuration files which contain secret data, and is used to rotate TLS certificates as well as to manage the encryption keys and tokens used by the other services.

**WireGuard**

WireGuard is used to secure communications between cluster nodes. This allows us to securely keep a private network even between multiple regions and cloud providers.

## Installation

1. Configure your environment. The requirements:
   - `HCLOUD_TOKEN` is the Hetzner Cloud token.
   - `ssh-add -L` needs to show at least one key (it will be used as the key for the created instances).
2. Run `robo production terraform-infra apply` to sync the infrastructure. This command requires confirmation before continuing, but you can also use `plan` or any other Terraform arguments.
3. Run `robo production ansible` to apple the configuration. The change detection does not work correctly on the first run, so `-CD` cannot be used here. They will work after a run has completed at least once.
  - The Vault creation will drop `vault.txt` in the repository root, which contains the Vault unseal keys and root token. Store these safely and delete the file.
  - Optionally, `robo production verify` can be used to diagnose some basic issues now and in the future.
4. Connect to the machine using ssh (use `robo production master_ip` for the IP address) and follow the [WireGuard docs](./docs/wireguard.md) to set up the initial peer.

Next steps:

- Deploy jobs with Nomad.
  - Write a Terraform script to do this.

### Local environment setup

To access the cluster from your local machine:

1. Install the generated CA at `bootstrap/data/ca.crt` to configure SSL. You can install it using Keychain Access.app into the login keychain, but you will need to manually trust the certificate, which is done from the certificate info window under "Trust".
  - This also enables UI access in the browser: [Consul](https://172.30.0.1:8501/) | [Vault](https://172.30.0.1:8200/) | [Nomad](https://172.30.0.1:4646/)
2. Configure WireGuard and connect it.
3. Set up local DNS to use Consul.
4. Use `eval $(robo env)` to get the necessary environment variables.

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
