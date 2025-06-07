local utils = import 'utils.libsonnet';

{
  priority: 20,

  manifests(_config): {
    local module = self,

    cronJob: {
      apiVersion: 'batch/v1',
      kind: 'CronJob',
      metadata: {
        name: 'backup',
        namespace: 'admin',
      },
      spec: {
        schedule: '@monthly',
        jobTemplate: {
          spec: {
            backoffLimit: 4,
            template: {
              metadata: {
                name: 'backup',
              },
              spec: {
                restartPolicy: 'Never',
                containers: [
                  {
                    name: 'backup',
                    image: 'alpine:latest',

                    env: [
                      { name: 'RESTIC_CACHE_DIR', value: '/cache' },
                    ],
                    envFrom: [
                      { secretRef: { name: 'backup-secrets' } },
                    ],
                    volumeMounts: [
                      { name: 'backup-script', mountPath: '/app' },
                      { name: 'var-lib-rancher', mountPath: '/var/lib/rancher' },
                      { name: 'opt-backup-cache', mountPath: '/cache' },
                    ],

                    command: ['/app/backup.sh'],
                  },
                ],
                volumes: [
                  {
                    name: 'backup-script',
                    configMap: {
                      name: module.configMap.metadata.name,
                      defaultMode: std.parseOctal('0755'),
                    },
                  },
                  {
                    name: 'var-lib-rancher',
                    hostPath: { path: '/var/lib/rancher' },
                  },
                  {
                    name: 'opt-backup-cache',
                    hostPath: {
                      path: '/opt/backup-cache',
                      type: 'DirectoryOrCreate',
                    },
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
        name: 'backup-script-',
      },
      data: {
        'backup.sh': importstr 'backup.sh',
      },
    }),
  },
}
