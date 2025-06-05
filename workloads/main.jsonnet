local config = import 'config.libsonnet';

local decls = {
  backup: import 'backup/main.libsonnet',
  core: import 'core/main.libsonnet',
  cert_manager: import 'cert-manager/main.libsonnet',
  dashboard: import 'dashboard/main.libsonnet',
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
    local globalConfig = { domain: config.domain };
    local moduleConfig = globalConfig + config.workloads[workload];
    local manifests = module.manifests(moduleConfig);
    extractManifests(manifests);

{
  decls: decls,
  config: config,
  manifests: manifests,
}
