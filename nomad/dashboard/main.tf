data "local_file" "index_html" {
  filename = "${path.module}/index.html"
}

variable "base_domain" {
  type = string
}

resource "nomad_job" "dashboard" {
  jobspec = templatefile("${path.module}/dashboard.hcl.tpl", {
    base_domain = var.base_domain
    index_html  = data.local_file.index_html.content
  })
}
