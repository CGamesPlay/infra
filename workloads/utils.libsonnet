{
  // Helper to hash config data for use as an immutable ConfigMap object.
  // The existing metadata.name is treated as a prefix and should end in
  // "-".
  immutable_config_map(manifest): manifest {
    metadata+: {
      name: manifest.metadata.name + std.md5(std.manifestJson(manifest.data)),
    },
    immutable: true,
  },

  service_ingress(config, metadata, app, port, host=null, middlewares=[]): {
    local host1 = if host == null then app + '.' + config.domain else host,

    service: {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: metadata,
      spec: {
        selector: {
          app: app,
        },
        ports: [
          { port: port },
        ],
      },
    },
    ingress: {
      apiVersion: 'networking.k8s.io/v1',
      kind: 'Ingress',
      metadata: metadata {
        annotations+: {
          'cert-manager.io/cluster-issuer': 'letsencrypt',
        } + if middlewares != [] then
          { 'traefik.ingress.kubernetes.io/router.middlewares': std.join(',', middlewares) }
        else {},
      },
      spec: {
        rules: [
          {
            host: host1,
            http: {
              paths: [
                {
                  path: '/',
                  pathType: 'Prefix',
                  backend: {
                    service: {
                      name: app,
                      port: { number: port },
                    },
                  },
                },
              ],
            },
          },
        ],
        tls: [
          if config.wildcardCertificate && (std.endsWith(host1, '.' + config.domain) || host1 == config.domain) then
            {
              secretName: 'tls-' + config.domain,
              hosts: [config.domain, '*.' + config.domain],
            }
          else
            {
              secretName: app + '-tls',
              hosts: [host1],
            },
        ],
      },
    },
  },

  // This function substitutes all occurrences of `${foo}` with
  // `vars.foo` in the template.
  varSubstitute(template, vars):
    local subNext(prefix, rest) =
      local parts = std.splitLimit(rest, '$', 1);
      if std.length(parts) == 1 then
        // No more substitutions in string
        prefix + rest
      else if parts[1][0] == '$' then
        // Escaped $
        subNext(prefix + parts[0] + '$', parts[1][1:])
      else if parts[1][0] == '{' then
        // Make a substitution
        local parts2 = std.splitLimit(parts[1][1:], '}', 1);
        subNext(prefix + parts[0] + vars[parts2[0]], parts2[1])
      else
        // Unescaped $
        subNext(prefix + parts[0] + '$', parts[1]);
    subNext('', template),
}
