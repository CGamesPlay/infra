{
  domain: 'lvh.me',
  workloads: {
    core: {
      secrets: importstr 'secrets.yml',
      authelia_users_yaml: importstr 'authelia-users.yml',
    },
    whoami: {},
  },
}
