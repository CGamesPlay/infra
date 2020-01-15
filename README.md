# Personal Cloud IaC

This is the repo I use for my personal cloud server, hosted as a VPS. This draws heavily from [Funky Penguin's Geek Cookbook](https://geek-cookbook.funkypenguin.co.nz/), but uses a single node rather than a swarm and is targeted against Traefik 2.

## Services

- Traefik load balancer, with dashboard protected by Keycloak.
- Keycloak IDM.
- Portainer management console.
- Heimdall as a launcher.

## Deploying a new service

Services each live in their own directory, and are driven primarily by a `docker-compose.yml` file. The `example` directory includes several configuration options that can be used to design other services.

#### Environment variables

##### `CLOUD_ENV`

This is either `prod` or `dev`. Its primary use is changing the overrides file: `docker-compose.$CLOUD_ENV.yml`, but it's also available for use in the environment.

##### `BASE_DOMAIN`

This is the main domain that all services are rooted at. They will become subdomains under this.

##### `DATA_DIR`

This is a local path that can be used for persistent volumes. Best practice is for each stack to create volumes under a directory matching the stack name, so for example `${DATA_DIR}/myapp/db`.

## Starting from scratch

The following process is necessary to "bootstrap" a machine.

1. Set up the environment variables:

   1. `CLOUD_ENV` to either `dev` or `prod`.
   2. `BASE_DOMAIN` and `DATA_DIR` based on your configuration.

2. Create the traefik network.

   `docker network create traefik`

3. Start the traefik service.

   `./compose.sh traefik up -d`

4. Start keycloak.

   `./compose.sh keycloak up -d app`

5. Open `keycloak.$BASE_DOMAIN` and log in with admin / password.

6. Change the admin credentials.

7. Create a new client called `cloud-admin`

   - Access type: confidential
   - Redirect URI: `http://forwardauth.$BASE_DOMAIN/*`

8. Copy `keycloak/forward-auth.env.example` to `keycloak/forward-auth.$CLOUD_ENV.env` and edit.

9. Start keycloak forwardauth.

   `./compose.sh keycloak up -d`