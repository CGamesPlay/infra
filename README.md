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

The default cluster configuration is an empty k3s installation. Use `argc sync` to deploy the workloads from `config.libsonnet` to the cluster.

- [Traefik Dashboard](https://traefik.lvh.me/) - accessible via the self-signed certificate. Log in with authelia / authelia.
- `eval "$(argc activate $ENVIRONMENT)"` - set up the `KUBECONFIG` variable and others in the current terminal session. Useful to put this in your `.envrc` for use with direnv.
- `kubectl` - Use `env/local/kubeconfig.yml` to access
- `kapp` - Use `env/local/kubeconfig.yml` to access
- `argc sync` - Run this to sync all workloads in `config.libsonnet`. This is equivalent to running `argc apply $WORKLOAD` for each workload configured.
- `argc render $WORKLOAD` - Show the rendered manifest for the given workload.
- `argc diff $WORKLOAD` - Show a diff of the rendered manifest and the current cluster state.
- `argc apply $WORKLOAD` - Apply the rendered manifest to the cluster.

Workloads are managed using kapp, and can be deleted using `kapp delete`. There is presently no support for automatically pruning workloads that you remove from `config.libsonnet`.

#### Deprovisioning Workloads

You can use `kapp delete -a $NAME` to delete all resources associated with a workload. Note that the default reclaim policy of dynamically-provisioned PersistentVolumes (e.g. local-path PVs) is "Delete". You may want to change this to "Retain". Since the PersistentVolume isn't specified in the jsonnet configuration, you should [do this using kubectl](https://kubernetes.io/docs/tasks/administer-cluster/change-pv-reclaim-policy/#changing-the-reclaim-policy-of-a-persistentvolume).

To reuse this volume at a later date, you should patch it again to set a claimRef matching the original PersistentVolumeClaim, then deploy the workload as usual.

```bash
kubectl patch pv <your-pv-name> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
kubectl get pv # Verify that change has been applied.

# Untested commands
kubectl patch pv <your-pv-name> -p '{"spec":{"claimRef":{"namespace":"default","name":"your-pvc-name"}}}'
```

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

You may want to set up your SSH config for access to the server. This is fine, but please note that `argc upgrade` will cause the SSH host key to change. You can avoid this by using the `Hostname` directive in your SSH config. The `argc upgrade` script will automatically update the host key when the upgrade is performed.

```bash
# Example configuration for SSH
Host my.cluster.dns
  Hostname 188.245.147.159
  User root
```

## Repo Organization

Here are the main directories in this repository

- `env/$ENVIRONMENT` describes a single environment. My production deployment is checked in here, which you can see as an example.
- `driver/` is a directory containing the scripts to manage the infrastructure powering the cluster. These are not meant to be run directly, instead accessed through the root `Argcfile.sh`.
- `workloads/` is the main Jsonnet directory.
  - Subdirectories here correspond to individual workloads which can be enabled and configured using the environment's `config.libsonnet` file.

## Using Kubernetes

### Basic Maintenance

These are some basic commands that can be used for troubleshooting:

```bash
# View node status
kubectl get nodes
# Check control plane components
kubectl get componentstatuses
# Review Kubernetes events
kubectl get events -A
# List deployments (check for anything not fully ready)
kubectl get deployments -A
# Look for failed jobs
kubectl get job -A
```

### Deploying from CI/CD

Unclear!

### Common Issues

- If you change the server's primary IP addresses in the cloud provider console, it may be necessary to run `cloud-init clean -c network` and reboot in order for the server to detect the changes. Failing to do this may result in a partially updated network (e.g. IPv4 works but IPv6 does not).

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

- 2025-05-30: The infrastructure underwent a substantial change from Nomad to Kubernetes. The older version can be found [here](https://github.com/CGamesPlay/infra/tree/35120ca5e04795cad60536bc5f91c0c6f89f4d15). It uses Nomad, Consul, and Vault, as well as Ansible for managing the configuration of the server.
