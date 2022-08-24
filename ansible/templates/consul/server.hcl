server = true
bootstrap_expect = 1
ui_config {
  enabled = true
}
# Recommend using https://github.com/hashicorp/go-sockaddr to debug the
# bind_addr template string.
bind_addr = "{{GetInterfaceIP \"wg0\"}}"
recursors = [ "1.1.1.1" ]
