#!/usr/bin/bash
set -eu

python3 -m venv /opt/ansible/.venv
cd /opt/ansible
cat >requirements.txt <<'EOF'
ansible==6.3.0
ansible-core==2.13.3
cffi==1.15.1
cryptography==37.0.4
Jinja2==3.1.2
MarkupSafe==2.1.1
packaging==21.3
pycparser==2.21
pyparsing==3.0.9
PyYAML==6.0
resolvelib==0.8.1
EOF
.venv/bin/pip3 install -r requirements.txt
./.venv/bin/ansible-pull -U https://github.com/CGamesPlay/infra -d /opt/ansible/infra -i localhost, private-server/ansible/site.yml
