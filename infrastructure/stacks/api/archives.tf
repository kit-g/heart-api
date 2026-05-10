resource "null_resource" "build_dart_api" {
  # Trigger a rebuild if the source code or Makefile changes
  triggers = {
    source_code_hash = join(
      "", [
        for f in fileset(
          "${path.module}/../../../api", "**/*.dart"
          ) : filebase64sha256(
          "${path.module}/../../../api/${f}"
        )
      ]
    )
    makefile_hash = filebase64sha256("${path.module}/../../../api/Makefile")
  }

  provisioner "local-exec" {
    working_dir = "${path.module}/../../../api"
    command     = <<EOT
      mkdir -p ../build/api
      dart pub get
      dart compile exe bin/main.dart \
        --target-os=linux \
        --target-arch=arm64 \
        -o ../build/api/bootstrap
    EOT
  }
}

data "archive_file" "api" {
  depends_on  = [null_resource.build_dart_api]
  type        = "zip"
  source_file = "${path.module}/../../../build/api/bootstrap"
  output_path = "${path.module}/../../../build/api.zip"
}
