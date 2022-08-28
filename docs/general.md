# General Checklist

This checklist is used to verify that everything is operating correctly. It's good to run this checklist after any system maintenance.

- [ ] VPN connects.
- [ ] SSH connects.
- [ ] `robo production verify` reports no problems.
- [ ] [Nomad dashboard](https://nomad.service.consul:4646) is accessible.
- [ ] [Consul](https://consul.service.consul:8501/ui/nbg1/services) reports running services:
  - [ ] Joplin
  - [ ] Seafile
  - [ ] Chess2Online
  - [ ] Launa
