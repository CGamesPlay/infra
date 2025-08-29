{
  domain: 'cluster.cgamesplay.com',
  wildcardCertificate: true,

  workloads: {
    backup: {},
    'cert-manager': {
      email: 'ry@cgamesplay.com',
      staging: false,
      hostedZoneID: 'Z06017189PYZQUONKTV4',
    },
    core: {
      secrets: importstr 'secrets.yml',
      authelia_users_yaml: importstr 'authelia-users.yml',
    },
    chess2online: {},
    dashboard: {},
    seafile: {},
  },
}
