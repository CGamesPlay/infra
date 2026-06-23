{
  // Declares the typical Ingress needed to expose a service via Traefik. The
  // matching Service object must expose a port named 'http'.
  local traefik_ingress(module_config, _ingress_config) = {
    local domain = module_config.domain,
    local ingress_config = {
      // Required. Name of the workload.
      app: error 'App name required',
      // Optional. Override namespace.
      namespace: null,
      // Optional. Override the public host.
      host: _ingress_config.app + '.' + domain,
      // Optional. Traefik middlewares to apply.
      middlewares: [],
    } + _ingress_config,

    apiVersion: 'networking.k8s.io/v1',
    kind: 'Ingress',
    metadata: {
      name: ingress_config.app,
      annotations: {
        'cert-manager.io/cluster-issuer': 'letsencrypt',
      } + if ingress_config.middlewares != [] then
        { 'traefik.ingress.kubernetes.io/router.middlewares': std.join(',', ingress_config.middlewares) }
      else {},
    } + if ingress_config.namespace != null then { namespace: ingress_config.namespace } else {},
    spec: {
      rules: [
        {
          host: ingress_config.host,
          http: {
            paths: [
              {
                path: '/',
                pathType: 'Prefix',
                backend: {
                  service: {
                    name: ingress_config.app,
                    port: { name: 'http' },
                  },
                },
              },
            ],
          },
        },
      ],
      tls: [
        if module_config.wildcardCertificate && (std.endsWith(ingress_config.host, '.' + domain) || ingress_config.host == domain) then
          {
            secretName: 'tls-' + domain,
            hosts: [domain, '*.' + domain],
          }
        else
          {
            secretName: ingress_config.app + '-tls',
            hosts: [ingress_config.host],
          },
      ],
    },
  },
  traefik_ingress: traefik_ingress,

  // Typical service with optional ingress configuration.
  simple_service(module_config, _service_config):
    local domain = module_config.domain;
    local service_config = {
      // Required. Name of the workload.
      app: error 'App name required',
      // Optional. Override namespace.
      namespace: null,
      // Required. Port to connect to.
      port: error 'Port required',
      // Optional. Disable the default ingress route.
      ingress: true,
    } + _service_config;
    {
      service: {
        apiVersion: 'v1',
        kind: 'Service',
        metadata: {
          name: service_config.app,
          namespace: service_config.namespace,
        },
        spec: {
          selector: {
            app: service_config.app,
          },
          ports: [
            { name: 'http', port: service_config.port },
          ],
        },
      },
      ingress: if service_config.ingress then traefik_ingress(module_config, service_config) else {},
    },

  // Produce a mutable ConfigMap with a stable name. Its content hash is
  // exposed as a HIDDEN field (config_hash::): accessible to sibling manifests
  // as module.<key>.config_hash, but never serialized into the actual ConfigMap
  // object. Workloads that consume this ConfigMap mirror that value onto their
  // pod-template annotation 'configmap-hash' so the workload rolls when config
  // changes (replaces the old immutable-configmap pattern; keeps one stable
  // object and surfaces changes as a small diff).
  config_map(manifest): manifest {
    config_hash:: std.md5(std.manifestJson(manifest.data)),
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

  // This is really useful if you want to make an arry out of
  // constitutent parts which may be lists or optional.
  //
  // Returns the passed array with:
  // 1. Nulls removed
  // 2. Any elements who are arrays flattened into this arry.
  join(a):
    local notNull(i) = i != null;
    local maybeFlatten(acc, i) = if std.type(i) == 'array' then acc + i else acc + [i];
    std.foldl(maybeFlatten, std.filter(notNull, a), []),
}
