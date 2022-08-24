#!/bin/bash
set -ueo pipefail

consul acl policy create -name anonymous -rules - <<'EOF'
node_prefix "" {
  policy = "read"
}

service_prefix "" {
  policy = "read"
}
EOF
consul acl set-agent-token agent "$CONSUL_HTTP_TOKEN"
consul acl token update -id 00000000-0000-0000-0000-000000000002 -policy-name anonymous -description "Anonymous Token"

consul acl policy create -name vault -rules - <<'EOF'
key_prefix "vault/" {
  policy = "write"
}

service "vault" {
  policy = "write"
}

node_prefix "" {
  policy = "read"
}

agent_prefix "" {
  policy = "read"
}

session_prefix "" {
  policy = "write"
}
EOF
