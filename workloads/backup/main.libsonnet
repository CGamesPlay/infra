local utils = import 'utils.libsonnet';

{
  priority: 20,

  manifests(_config): {
    local module = self,

    cronJob: {
      apiVersion: 'batch/v1',
      kind: 'CronJob',
      metadata: {
        name: 'restic',
        namespace: 'admin',
      },
      spec: {
        schedule: '@monthly',
        jobTemplate: {
          spec: {
            backoffLimit: 4,
            template: {
              metadata: {
                name: 'restic',
              },
              spec: {
                restartPolicy: 'Never',
                containers: [
                  {
                    name: 'backup',
                    image: 'alpine:latest',

                    envFrom: [
                      { secretRef: { name: 'restic' } },
                    ],
                    volumeMounts: [
                      { name: 'restic-script', mountPath: '/app' },
                      { name: 'var-lib-rancher', mountPath: '/var/lib/rancher' },
                    ],

                    command: ['/app/backup.sh'],
                  },
                ],
                volumes: [
                  {
                    name: 'restic-script',
                    configMap: {
                      name: module.configMap.metadata.name,
                      defaultMode: std.parseOctal('0755'),
                    },
                  },
                  {
                    name: 'var-lib-rancher',
                    hostPath: { path: '/var/lib/rancher' },
                  },
                ],
              },
            },
          },
        },
      },
    },

    configMap: utils.immutable_config_map({
      apiVersion: 'v1',
      kind: 'ConfigMap',
      metadata: {
        namespace: 'admin',
        name: 'restic-script-',
      },
      data: {
        'backup.sh': importstr 'backup.sh',
      },
    }),
  },
}
