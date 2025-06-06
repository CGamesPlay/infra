{
  domain: 'cluster.cgamesplay.com',
  wildcardCertificate: true,

  workloads: {
    core: {
      secrets: importstr 'secrets.yml',
      authelia_users_yaml: importstr 'authelia-users.yml',
    },
    'cert-manager': {
      email: 'ry@cgamesplay.com',
      staging: false,
      hostedZoneID: 'Z06017189PYZQUONKTV4',
    },
    dashboard: {},
    seafile: {},
    'open-webui': {},
    chess2online: {},
  },
}
