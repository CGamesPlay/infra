local core = import 'core/main.libsonnet';
local utils = import 'utils.libsonnet';

local index_html = (
  function()
    local template = importstr 'index.html';
    template
)();

{
  priority: 100,

  manifests(_config): {
    local module = self,
    local config = {} + _config,

    deployment: {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: {
        name: 'dashboard',
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            app: 'dashboard',
          },
        },
        template: {
          metadata: {
            labels: {
              app: 'dashboard',
            },
          },
          spec: {
            containers: [
              {
                name: 'dashboard',
                image: 'halverneus/static-file-server',
                volumeMounts: [
                  { name: 'web-content', mountPath: '/web' },
                ],
                resources: {
                  limits: {
                    memory: '50Mi',
                  },
                },
              },
            ],
            volumes: [
              {
                name: 'web-content',
                configMap: { name: module.configMap.metadata.name },
              },
            ],
          },
        },
      },
    },

    configMap: utils.immutable_config_map({
      apiVersion: 'v1',
      kind: 'ConfigMap',
      metadata: {
        name: 'dashboard-files-',
      },
      data: {
        'index.html': utils.varSubstitute(index_html, {
          domain: config.domain,
        }),
      },
    }),


    serviceIngress: utils.service_ingress(config, { name: 'dashboard' }, 'dashboard', 8080, host=config.domain, middlewares=[core.auth_middleware]),
  },
}
