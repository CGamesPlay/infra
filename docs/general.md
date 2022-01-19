# General Checklist

This checklist is used to verify that everything is operating correctly. It's good to run this checklist after any system maintenance.

- [ ] VPN connects.
- [ ] SSH connects.
- [ ] [Nomad dashboard](https://nomad.service.consul:4646) is accessible.
- [ ] Vault has been unsealed.
- [ ] [Consul](https://consul.service.consul:8501/ui/nbg1/services) reports running services:
  - [ ] Joplin
  - [ ] Seafile
  - [ ] Chess2Online
  - [ ] Launa