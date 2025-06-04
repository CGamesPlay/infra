# Personal Cloud IaC

This is the repo I use for [my personal cloud server](https://cgamesplay.com/post/2021/10/27/creating-my-personal-cloud-with-hashicorp/), hosted as a VPS.

**Features:**

- Single-node [K3s](https://k3s.io) installation.
- Encryption at rest for Kubernetes secrets, etcd, and all container persistent volumes.
- Atomic upgrades by storing all stateful data on an external volume.
- Easily create local environments for testing.
- Automatic SSL certificates via [LetsEncrypt](https://letsencrypt.org).
- IPv4 and IPv6 support.
- A [variety of workloads](./workloads) that I've deployed. Some highlights:
  - [backup](./workloads/backup) - back up the system using [Restic](https://restic.net) on a periodic basis.
  - [registry](./nomad/registry) - host a private [Docker](https://www.docker.com/) registry, which can be referenced by other Nomad jobs.
  - See the full list [here](./workloads).

## System components

**K3s**

[K3s](https://k3s.io) is a lightweight Kubernetes distribution which includes useful single-node-cluster features like host path volumes, a LoadBalancer, and [Traefik](https://traefik.io/traefik/).

**Jsonnet**

[Jsonnet](https://jsonnet.org/) is used to declare the desired Kubernetes workloads. The configuration boils down to a series of manifest files which are applied using either kubectl or [kapp](https://carvel.dev/kapp/).

**SOPS**

[Mozilla SOPS](https://getsops.io/docs/) is used to encrypt Kubernetes secrets in this repository, and combined with [sops-secrets-operator](https://github.com/isindir/sops-secrets-operator/) to decrypt them on the cluster. We use [Age](https://age-encryption.org/) to as the encryption provider.

## Installation

### 1. Choose Technology

Choose the technology you will deploy to:

- [Lima](https://lima-vm.io) is available for quickly spinning up test clusters on a local macOS machine.
- [Hetzner Cloud](https://www.hetzner.com) is available for creating a cloud-hosted cluster.

### 2. Configure Dependencies

You'll need [argc](https://github.com/sigoden/argc/) installed, as well as a variety of other utilities that will be printed when you use a command that requires them.

- The Lima driver requires that `limactl` is installed.
- The Hetzner driver requires that `hcloud` is installed. For Hetzner, your should also create an empty project to host the resources you will use. Set up `hcloud` using `hcloud context` or by setting `HCLOUD_TOKEN`.

Generate an age key if you don't already have one: `age-keygen -o development.key`. The public key will be printed to the console; it should look like `age1qal59j7k2hphhmnmurg4ymj9n32sz5dgnx5teks3ch72n4wjfevsupgahc`.

### 3. Initialize Cluster

Run `argc init --driver=lima --age $AGE_PUBLIC_KEY local` to create a cluster named `local` using the Lima driver. `$AGE_PUBLIC_KEY` should be your age public key. This command should take a few minutes to run and should stream logs throughout the process.

At the end, the script will print the disk encryption password. It is important that you store this somewhere safe; it is necessary to reboot or upgrade the server.

To use the Hetzner driver, run `argc init --help` and `argc init --driver=hetzner --driver-help` to see the arguments you need to pass. At a minimum, you'll need to use `--location`, `--type`, and `--size`.

You can create any number of clusters. Each stores its configuration in a subdirectory of `env/`. Looking at the local cluster in `env/local/`, we see these files:

- `kubeconfig.yml` is the kubeconfig you can use to access the cluster.
- `sops-age-recipient.txt` is the public key of the cluster's sops-secret-operator.
- `config.libsonnet` contains the configuration for the workloads.
- `secrets.yml` contains the environment-specific SOPS-encrypted secrets. Each document in this YAML file should be a SopsSecret object, and you need to use a separate object for each namespace you want to add secrets to.
- `authelia-users.yml` contains a sample Authelia users database.

### 4. Use Cluster

The default cluster configuration is an empty k3s installation. Use `argc sync` to deploy the workloads from `main.tf` to the cluster.

- [Dashboard](https://lvh.me/) - accessible via the self-signed certificate. Log in with authelia / authelia.
- `kubectl` - Use `env/local/kubeconfig.yml` to access
- `kapp` - Use `env/local/kubeconfig.yml` to access
- `argc sync local` - Run this to sync all workloads in `config.libsonnet`. This is equivalent to running `argc apply local $WORKLOAD` for each workload configured.
- `argc render local $WORKLOAD` - Show the rendered manifest for the given workload.
- `argc diff local $WORKLOAD` - Show a diff of the rendered manifest and the current cluster state.
- `argc apply local $WORKLOAD` - Apply the rendered manifest to the cluster.

Note that there presently isn't any delete support for workloads. You can manually delete a workload using something like `argc render local $WORKLOAD | kubectl delete -f -`, before removing the workload from the `config.libsonnet` file.

### 5. Upgrade The Server

**Option A: My Server is a "pet"**

You can follow the normal [K3s upgrade guide](https://docs.k3s.io/upgrades), as well as the normal [Ubuntu upgrade guide](https://documentation.ubuntu.com/server/how-to/software/upgrade-your-release/index.html).

**Option B: My server is "cattle"**

It is also possible to simply swap out the server for a new one using the same data drive. This method gives a fresh install of k3s from a known-good image.

To use this second approach, see `argc upgrade --help` and `argc upgrade --driver-help $ENVIRONMENT` for the available options. The basic approach looks like this:

1. Create a snapshot of the current server to roll back to if something happens: `hcloud server create-image`
2. Replace your server with a new one using `argc upgrade`
3. Unseal the server with `argc unseal`
4. Verify everything works. If you need to roll back to the previous version, use the snapshot you created in step 1 (e.g. `argc upgrade $ENVIRONMENT --image=my-snapshot-id`).
5. Delete the snapshot once you are happy with the upgrade.

### 6. Clean Up

Once you no longer need an environment, use `argc destroy` to remove it. This will delete all local/cloud resources, and remove the `env/` subdirectory.

### 7. Prepare for Production

Here is a checklist of things you should do when you are ready to deploy your cluster to production.

1. Turn on accidental deletion protection for the volume and primary IPs: `hcloud volume enable-protection` and `hcloud primary-ip enable-protection`.
1. Configure DNS for the main domain and subdomains.

## Repo Organization

Here are the main directories in this repository

- `env/$ENVIRONMENT` describes a single environment. My production deployment is checked in here, which you can see as an example.
- `driver/` is a directory containing the scripts to manage the infrastructure powering the cluster. These are not meant to be run directly, instead accessed through the root `Argcfile.sh`.
- `workloads/` is the main Jsonnet directory.
  - Subdirectories here correspond to individual workloads which can be enabled and configured using the environment's `config.libsonnet` file.

## Using Nomad

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

## Security Model

This is a toy project for personal use. As a result, the security model has been simplified from the normal one that you would encounter in a production system. At its core, the key difference is that a single-node system will be fully compromised if root access is gained on that node. The key implication of this is: **if a job escapes its sandbox, everything is compromised.** Specifically:

- Access to the root privileges on the host system can be used to read the unencrypted contents of the cluster's drive.
- Access to kube-apiserver can be used to run an arbitrary pod with root privileges on the host system.
- Helm charts installed from URLs can be modified at any time in the future to run an arbitrary pods with root privileges on the host system.

The steps required to make this setup "production-ready" are:

1. Set up [Pod Security Admissions](https://kubernetes.io/docs/concepts/security/pod-security-admission/) to prevent pods from being able to access resources that they shouldn't (host system resources, kube-system namespace, etc).
2. Follow the [K3s CIS Hardening Guide](https://docs.k3s.io/security/hardening-guide).
   - Note: the Kubernetes-native secrets encryption is not used; instead the entire etcd store is encrypted using full disk encryption.

## Changes

- 2025-05-30: The infrastructure underwent a substantial change from Nomad to Kubernetes. The older version can be found [here](https://github.com/CGamesPlay/infra/commit/35120ca5e04795cad60536bc5f91c0c6f89f4d15). It uses Nomad, Consul, and Vault, as well as Ansible for managing the configuration of the server.
