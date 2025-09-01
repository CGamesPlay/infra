local utils = import '../utils.libsonnet';

{
  priority: 100,

  manifests(_config): {
    local module = self,
    local config = {
      image_tag: '0.6.15',
    } + _config,

    deployment: {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: {
        name: 'open-webui',
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            app: 'open-webui',
          },
        },
        template: {
          metadata: {
            labels: {
              app: 'open-webui',
            },
          },
          spec: {
            containers: [
              {
                name: 'open-webui',
                image: 'ghcr.io/open-webui/open-webui:' + config.image_tag,
                ports: [
                  {
                    containerPort: 8080,
                  },
                ],
                env: [
                  {
                    name: 'WEBUI_SECRET_KEY',
                    valueFrom: {
                      secretKeyRef: {
                        name: 'open-webui-secrets',
                        key: 'WEBUI_SECRET_KEY',
                      },
                    },
                  },
                  {
                    name: 'ANTHROPIC_API_KEY',
                    valueFrom: {
                      secretKeyRef: {
                        name: 'open-webui-secrets',
                        key: 'ANTHROPIC_API_KEY',
                      },
                    },
                  },
                  {
                    name: 'OPENAI_API_KEY',
                    valueFrom: {
                      secretKeyRef: {
                        name: 'open-webui-secrets',
                        key: 'OPENAI_API_KEY',
                      },
                    },
                  },
                  {
                    name: 'GOOGLE_PSE_API_KEY',
                    valueFrom: {
                      secretKeyRef: {
                        name: 'open-webui-secrets',
                        key: 'GOOGLE_PSE_API_KEY',
                      },
                    },
                  },
                  {
                    name: 'GOOGLE_PSE_ENGINE_ID',
                    valueFrom: {
                      secretKeyRef: {
                        name: 'open-webui-secrets',
                        key: 'GOOGLE_PSE_ENGINE_ID',
                      },
                    },
                  },
                  {
                    name: 'WEBUI_URL',
                    value: 'https://open-webui.' + config.domain + '/',
                  },
                  {
                    name: 'ENABLE_OLLAMA_API',
                    value: 'False',
                  },
                  {
                    name: 'RAG_EMBEDDING_ENGINE',
                    value: 'openai',
                  },
                  {
                    name: 'AUDIO_STT_ENGINE',
                    value: 'openai',
                  },
                  {
                    name: 'ENABLE_RAG_WEB_SEARCH',
                    value: 'True',
                  },
                  {
                    name: 'RAG_WEB_SEARCH_ENGINE',
                    value: 'google_pse',
                  },
                  {
                    name: 'RAG_WEB_SEARCH_RESULT_COUNT',
                    value: '3',
                  },
                  {
                    name: 'RAG_WEB_SEARCH_CONCURRENT_REQUESTS',
                    value: '10',
                  },
                ],
                volumeMounts: [
                  {
                    name: 'data',
                    mountPath: '/app/backend/data',
                  },
                ],
                resources: {
                  requests: {
                    memory: '512Mi',
                  },
                  limits: {
                    memory: '1Gi',
                  },
                },
                livenessProbe: {
                  httpGet: {
                    path: '/health',
                    port: 8080,
                  },
                  initialDelaySeconds: 30,
                  periodSeconds: 30,
                  timeoutSeconds: 10,
                },
              },
            ],
            volumes: [
              {
                name: 'data',
                persistentVolumeClaim: {
                  claimName: 'open-webui-data',
                },
              },
            ],
          },
        },
      },
    },

    pvc: {
      apiVersion: 'v1',
      kind: 'PersistentVolumeClaim',
      metadata: {
        name: 'open-webui-data',
      },
      spec: {
        accessModes: ['ReadWriteOnce'],
        resources: {
          requests: {
            storage: '10Gi',
          },
        },
      },
    },

    serviceIngress: utils.simple_service(config, { app: 'open-webui', port: 8080 }),
  },
}
