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
