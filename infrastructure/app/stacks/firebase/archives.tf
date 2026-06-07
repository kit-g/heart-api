# Placeholder zip so Terraform can create the Lambda. The real zip — service
# code + firebase-admin deps + the runtime SA cert — ships via CI
# (deploy-firebase.yml). `lifecycle.ignore_changes` on the function keeps TF
# from clobbering CI updates.
data "archive_file" "placeholder" {
  type        = "zip"
  output_path = "${path.module}/../../../../build/firebase.zip"

  source {
    content  = "def handler(event, context):\n    return {'batchItemFailures': []}\n"
    filename = "app.py"
  }
}