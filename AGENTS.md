This is an infrastructure-as-code repo for a self-hosted k3s cluster. Depending on the local configuration, one or more environments may be available for use in `env/NAME/`. Repository layout:

```
/                      # Repository root
/docs                  # Documentation
/driver                # "Drivers" which create the infrastructure
/env                   # Active environments
  /NAME                # Environment named NAME
    /config.libsonnet  # Main configuration file for the environment
    /driver            # Link to environment's driver script
    /kubeconfig.yml    # kubeconfig for environment
    /secrets.yml       # sops-encrypted secrets
    /sops-age-recipient.txt  # Server's sops public key
/workloads             # Definitions for k8s workloads
  /main.libsonnet      # Main entry point for k8s config
  /NAME                # Workload named NAME
    /README.md         # Workload-specific documentation
    /main.libsonnet    # Main workload configuration
```

Workloads are designed to allow configurations per-environment (set in `env/NAME/config.libsonnet`), and so typically look like this:

```jsonnet
{
  priority: 100,
  manifests(_config):
    local config = {
      optional_param: 'default value',
      required_param: error 'required_param is required',
    } + _config;
    {
      local module = self,

      // k8s manifests in jsonnet form
    },
}
```

### ## Commands

The `$CLUSTER_ENVIRONMENT` environment variable sets the name of the environment to work on (generally already set for you). A `$KUBECONFIG` is generally also available, so `kubectl` should work normally.

```bash
# See differences from current environment
$ argc diff $WORKLOAD
# Apply the changes to the environment
$ argc apply --yes $WORKLOAD  
# Learn more
$ argc --help
```

The user may or may not want you to modify the cluster; check with them beforehand.