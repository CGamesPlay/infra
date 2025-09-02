{
  domain: 'lvh.me',
  workloads: {
    core: {
      secrets: importstr 'secrets.yml',
    },
    whoami: {},
  },
}
