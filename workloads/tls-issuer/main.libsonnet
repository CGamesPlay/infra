// A small, controller-free replacement for cert-manager. A weekly CronJob runs
// `lego` (ACME DNS-01 via Route53) to mint the wildcard cluster certificate and
// the chess2online certificate, writing each into the namespaces that consume
// it. See README.md for the migration/rollout notes.
{
  priority: 10,

  manifests(_config): {
    local module = self,
    local config = {
      // Contact address for the ACME account.
      email: error 'email required for LetsEncrypt',
      // false -> LetsEncrypt production; true -> staging.
      staging: true,
      // true -> emit self-signed certs (no ACME/Route53). Useful for dev envs.
      selfSigned: false,
      // Route53 region (Route53 is global; lego still expects a region).
      region: 'eu-central-1',
      // Pinned lego release + sha256 of lego_v${version}_linux_amd64.tar.gz.
      legoVersion: '4.21.0',
      legoSha256: 'c8cc7fb636f8a5f1167e013dbd01485a72eb7393faf1776664c765a722cd6070',
      // Days-before-expiry threshold that triggers renewal.
      renewDays: 30,
      // Certificates to maintain. Each is minted once and written into every
      // listed namespace. secretName/domains must match what utils.libsonnet
      // (and any hand-written Ingress tls blocks) reference.
      //   { secretName, domains: [...], hostedZoneID, namespaces: [...] }
      certificates: error 'certificates list is required',
    } + _config,

    local ns = 'tls-issuer',
    local mode = if config.selfSigned then 'self-signed'
    else if config.staging then 'staging'
    else 'production',

    // Union of every namespace we write a secret into, and the secrets we write
    // into each — used to scope the writer RBAC as tightly as possible.
    local allNamespaces = std.set(std.flattenArrays([c.namespaces for c in config.certificates])),
    local secretsIn(namespace) =
      std.set([c.secretName for c in config.certificates if std.member(c.namespaces, namespace)]),

    namespace: {
      apiVersion: 'v1',
      kind: 'Namespace',
      metadata: { name: ns },
    },

    serviceAccount: {
      apiVersion: 'v1',
      kind: 'ServiceAccount',
      metadata: { name: 'tls-issuer', namespace: ns },
    },

    // One Role + RoleBinding per target namespace, granting the issuer SA write
    // access to exactly the named TLS secrets (plus create on the collection,
    // since `kubectl apply` of a not-yet-existing secret authorizes create).
    writerRoles: [
      {
        apiVersion: 'rbac.authorization.k8s.io/v1',
        kind: 'Role',
        metadata: { name: 'tls-issuer-writer', namespace: namespace },
        rules: [
          {
            apiGroups: [''],
            resources: ['secrets'],
            resourceNames: secretsIn(namespace),
            verbs: ['get', 'update', 'patch'],
          },
          {
            apiGroups: [''],
            resources: ['secrets'],
            verbs: ['create'],
          },
        ],
      }
      for namespace in allNamespaces
    ],

    writerRoleBindings: [
      {
        apiVersion: 'rbac.authorization.k8s.io/v1',
        kind: 'RoleBinding',
        metadata: { name: 'tls-issuer-writer', namespace: namespace },
        subjects: [{ kind: 'ServiceAccount', name: 'tls-issuer', namespace: ns }],
        roleRef: {
          apiGroup: 'rbac.authorization.k8s.io',
          kind: 'Role',
          name: 'tls-issuer-writer',
        },
      }
      for namespace in allNamespaces
    ],

    script: {
      apiVersion: 'v1',
      kind: 'ConfigMap',
      metadata: { name: 'tls-issuer-script', namespace: ns },
      data: { 'issue.sh': importstr 'issue.sh' },
    },

    local podSpec = {
      serviceAccountName: 'tls-issuer',
      restartPolicy: 'OnFailure',
      containers: [{
        name: 'issue',
        image: 'alpine/k8s:1.31.0',
        imagePullPolicy: 'IfNotPresent',
        command: ['/bin/sh', '/scripts/issue.sh'],
        // Route53 credentials come from the `aws-access-key` secret delivered by
        // the sops-secrets-operator into this namespace (keys AWS_ACCESS_KEY_ID
        // and AWS_SECRET_ACCESS_KEY).
        envFrom: [{ secretRef: { name: 'aws-access-key' } }],
        env: [
          { name: 'TLS_ISSUER_MODE', value: mode },
          { name: 'ACME_EMAIL', value: config.email },
          { name: 'AWS_REGION', value: config.region },
          { name: 'LEGO_VERSION', value: config.legoVersion },
          { name: 'LEGO_SHA256', value: config.legoSha256 },
          { name: 'RENEW_DAYS', value: std.toString(config.renewDays) },
          { name: 'CERTS_JSON', value: std.manifestJsonEx(config.certificates, '') },
        ],
        volumeMounts: [{ name: 'script', mountPath: '/scripts', readOnly: true }],
      }],
      volumes: [{
        name: 'script',
        configMap: { name: 'tls-issuer-script', defaultMode: 493 },  // 0755
      }],
    },

    cronJob: {
      apiVersion: 'batch/v1',
      kind: 'CronJob',
      metadata: { name: 'tls-issuer', namespace: ns },
      spec: {
        schedule: '0 22 * * 0',  // weekly, Sunday 22:00 UTC
        concurrencyPolicy: 'Forbid',
        successfulJobsHistoryLimit: 1,
        failedJobsHistoryLimit: 3,
        jobTemplate: {
          spec: {
            backoffLimit: 4,
            template: {
              metadata: {
                name: 'tls-issuer',
                // Roll the Job template whenever the script changes so a stale
                // renewal script never lingers between applies.
                annotations: { 'script-hash': std.md5(module.script.data['issue.sh']) },
              },
              spec: podSpec,
            },
          },
        },
      },
    },
  },
}
