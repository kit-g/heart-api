data "archive_file" "placeholder" {
  type        = "zip"
  output_path = "${path.module}/placeholder.zip"

  source {
    # code updates handled by a GH action
    content  = "def handler(event, context):\n    return {'batchItemFailures': []}\n"
    filename = "app.py"
  }
}
