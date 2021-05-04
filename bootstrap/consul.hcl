data_dir = "./data/consul"
ui = true
server = true
bootstrap_expect = 1

acl = {
  enabled = true
  default_policy = "deny"
  enable_token_persistence = true
}
