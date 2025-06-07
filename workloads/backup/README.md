# Backup with Restic

Uses [Restic](https://restic.readthedocs.io) to automatically create backups of the cluster periodically. This workload is only appropriate for a single-node cluster that stores all volumes using the built-in k3s local-path-provisioner.

## Installation

1. Merge the [secret.template.yml](./secret.template.yml) file with your environment's secrets.
1. Add `backup = {}` in your environment's `config.libsonnet` under the workloads.
1. Run `argc apply core && argc apply backup`.

## Trigger a manual backup

```bash
kubectl create job -n admin --from=cronjob/backup manual-backup
kubectl logs -n admin job/manual-backup -f
kubectl delete -n admin job/manual-backup
```

