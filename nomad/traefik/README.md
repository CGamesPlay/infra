# Traefik

The Traefik load balancer is the main ingress point for all public-facing services in the cluster. It is responsible for terminating SSL using LetsEncrypt and forwarding connections to the proper services.

## Installation

To set up Traefik to handle SSL for your cluster, first assign a DNS name to the nodes that will run Traefik. Ensure that all subdomains also point to the same IPs. Store in Consul the domain name as well as the contact email address for your SSL certificates:

```bash
consul kv put traefik/config/domain example.com
consul kv put traefik/config/email contact@example.com
```

No further configuration is necessary for Traefik.

## Usage

Traefik will scan the Consul catalog for additional services and automatically configure SSL and forwarding for them. To use this, apply these tags:

```hcl
service {
  tags = [
    "traefik.enable=true",
    "traefik.http.routers.${NOMAD_JOB_NAME}.tls.certresolver=le",
  ]
}
```

The usage of `${NOMAD_JOB_NAME}` means that the subdomain for the service will default to the job's name. If you want to customize the behavior, see [the Traefik documentation](https://doc.traefik.io/traefik/routing/routers/).

**Note:** Traefik is configured to automatically redirect all HTTP traffic to the corresponding HTTPS endpoint, regardless of any dynamic configuration.

### Debugging

The first place to look should be the [Traefik dashboard](https://172.30.0.1:8080). This will list all configured services and the rules required to access them. If something isn't listed there, check the [Consul dashboard](https://172.30.0.1:8501) to ensure that the service is properly registered and healthy.

It may be helpful to enable the DEBUG log level in Traefik, which will cause it to log to stdout every change in configuration.
