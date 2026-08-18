# Zulip

[Zulip](https://zulip.com) is an open-source team chat server. This workload runs the official Docker image ([docker-zulip](https://github.com/zulip/docker-zulip)) with its dependencies (PostgreSQL, memcached, RabbitMQ, Redis) as containers in a single pod, following the layout of the upstream Compose file. TLS terminates at Traefik; the container serves plain HTTP.

Memory is budgeted for a small installation (the upstream docs consider 2 GB RAM sufficient): the `zulip` container gets a 1536Mi limit, the rest of the pod roughly 700Mi. Queue workers are pinned to the threaded (low-memory) mode, because the container would otherwise size them from the host's memory rather than its limit.

## Installation

1. Add Zulip to the environment configuration:

   ```jsonnet
   zulip: {
     admin_email: 'you@example.com',
     mailer+: {
       enabled: true,
       host: 'smtp.example.com',
       user: 'zulip@example.com',
     },
     oidc+: { enabled: true },
   },
   ```

2. Generate the secret values and add them to the environment's secrets.yml, following `secret.template.yml`. Note that `zulip__social_auth_oidc_secret` must match the argon2 hash configured as the `zulip` OIDC client in the core workload's Authelia configuration.

3. Apply the workload. First boot runs the initial configuration and database migrations, and can take ten minutes or more. Watch progress with:

   ```bash
   kubectl logs -f deployment/zulip -c zulip
   ```

4. Generate a link to create the first organization:

   ```bash
   argc zulip-manage generate_realm_creation_link
   ```

   Open the link to create the organization and owner account.

## Notes

- **Backups**: Zulip dumps the database daily to `/data/backups` (`AUTO_BACKUP_ENABLED`), and the whole `/data` and database volumes are local-path PVCs covered by the backup workload's restic snapshots.
- **Upgrades**: bump `image_tag` (e.g. `12.2-0` → `13.0-0`) and apply; the entrypoint runs migrations on boot. Zulip supports upgrading at most one major version at a time.
- **Authentication**: email/password plus Authelia via generic OIDC (`/complete/oidc/` redirect). The Authelia middleware must not be attached to this workload's ingress: it would break Zulip's own login flow, API clients, and websockets.
- **RabbitMQ/Redis state** is transient (emptyDir), matching the upstream Helm chart's defaults. Pending queue work is lost on pod restarts.
