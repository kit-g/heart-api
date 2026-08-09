# Placeholder so the function resource can be created; the real code is
# shipped by CI (deploy-api.yml) via update-function-code, and
# `lifecycle.ignore_changes` on the function keeps TF from clobbering it.
#
# This replaced a local-exec `dart compile` of the working tree: a plan/apply
# used to build and deploy whatever was on the developer's disk — staged,
# dirty, or otherwise.
data "archive_file" "placeholder" {
  type        = "zip"
  output_path = "${path.module}/../../../../build/api.zip"

  source {
    content  = "#!/bin/sh\necho 'placeholder: real code is deployed by CI' >&2\nexit 1\n"
    filename = "bootstrap"
  }
}
