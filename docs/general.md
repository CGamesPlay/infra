# General Checklist

This checklist is used to verify that everything is operating correctly. It's good to run this checklist after any system maintenance.

- [ ] VPN connects.
- [ ] SSH connects.
- [ ] `robo production verify` reports no problems.
- [ ] [Nomad dashboard](https://nomad.service.consul:4646) is accessible.
- [ ] [Consul](https://consul.service.consul:8501/ui/nbg1/services) reports running services:
  - [ ] Joplin
  - [ ] Seafile
  - [ ] Chess2Online
  - [ ] Launa

## Recovering Vault after crash

If Vault is unsealed but we get errors like "**local node not active but active cluster node not found**", we need to [recover the Raft quorum](https://developer.hashicorp.com/vault/tutorials/raft/raft-lost-quorum).

1. Place the following file in `/opt/vault/raft/raft/peers.json`.
2. Restart Vault.
3. Unseal vault with `vault operator unseal`
4. Verify everything is good with `vault operator raft list-peers`

```json
[
  {
    "id": "master.node.consul",
    "address": "172.30.0.1:8201",
    "non_voter": false
  }
]
```

## Recovering after a Nomad crash

When Nomad crashes, things generally come back up normally. However, sometimes jobs get stuck with no allocations, and it's not possible to restart the jobs. Instead, purge the jobs using the Nomad UI, then rerun them from the original jobspecs.

Several related issues, dating back to 2016. Seems like HashiCorp doesn't care about this.

- [Unable to Start Job in Nomad GUI After Entering "Dead" State #17307](https://github.com/hashicorp/nomad/issues/17307)
- [Support rerunning of the same job via force flag #1576](https://github.com/hashicorp/nomad/issues/1576)

Note the "Start Job" button in the UI is completely broken in 1.6.2, but it's possible to "revert" to an older verison of the job which doesn't have the "stop" flag set. [#18547](https://github.com/hashicorp/nomad/issues/18547).

## Recovering after a Traefik failed deployment

In case Traefik is deployed with a configuration that disables public access to Vault and Nomad, the Terraform scripts will no longer be able to deploy. The easiest way to recover is to connect to the VPN, open [Nomad](https://nomad.service.consul:4646/), locate the Traefik job, and roll back to a known-good version. If this is not possible, you can manually render and deploy the Traefik nomad job.
