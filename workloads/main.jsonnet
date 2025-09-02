local config = import 'config.libsonnet';

// Config for kapp. This isn't actually applied to the cluster.
// https://carvel.dev/kapp/docs/v0.64.x/config/
local kappConfig = {
  apiVersion: 'kapp.k14s.io/v1alpha1',
  kind: 'Config',
  local pvcIgnoreAnnotations = ['volume.kubernetes.io/selected-node', 'volume.kubernetes.io/storage-provisioner'],
  diffAgainstExistingFieldExclusionRules: [
    {
      path: ['metadata', 'annotations', annotation],
      resourceMatchers: [
        { apiVersionKindMatcher: { apiVersion: 'v1', kind: 'PersistentVolumeClaim' } },
      ],
    }
    for annotation in pvcIgnoreAnnotations
  ],
};

local decls = {
  backup: import 'backup/main.libsonnet',
  core: import 'core/main.libsonnet',
  'cert-manager': import 'cert-manager/main.libsonnet',
  chess2online: import 'chess2online/main.libsonnet',
  dashboard: import 'dashboard/main.libsonnet',
  forgejo: import 'forgejo/main.libsonnet',
  'open-webui': import 'open-webui/main.libsonnet',
  seafile: import 'seafile/main.libsonnet',
  whoami: import 'whoami/main.libsonnet',
};

local extractManifests(obj) =
  if std.isObject(obj) then
    if std.objectHas(obj, 'apiVersion') && std.objectHas(obj, 'kind') then
      [obj]
    else
      std.flattenArrays([extractManifests(x) for x in std.objectValues(obj)])
  else if std.isArray(obj) then
    std.flattenArrays([extractManifests(x) for x in obj])
  else
    [];

local manifests(workload) =
  local module = std.get(decls, workload, error 'Invalid manifest: ' + workload);
  if !std.objectHas(config.workloads, workload) then
    error 'Manifest is disabled for environment: ' + workload
  else
    local globalConfig = {
      domain: config.domain,
      wildcardCertificate: std.get(config, 'wildcardCertificate', false),
      tcp_ports: std.get(config, 'tcp_ports', {}),
    };
    local moduleConfig = globalConfig + config.workloads[workload];
    local manifestTree = module.manifests(moduleConfig);
    extractManifests(manifestTree) + [kappConfig];

{
  decls: decls,
  config: config,
  manifests: manifests,
}
