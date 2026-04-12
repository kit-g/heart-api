resource "aws_dynamodb_table" "workouts" {
  name         = "workouts"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  attribute {
    name = "target_id"
    type = "S"
  }

  ttl {
    attribute_name = "scheduled_for_deletion_at"
    enabled        = true
  }

  local_secondary_index {
    name            = "connections_by_target_user_id"
    projection_type = "ALL"
    range_key       = "target_id"
  }

  deletion_protection_enabled = var.enable_deletion_protection

  point_in_time_recovery {
    enabled                 = var.point_in_time_recovery.enabled
    recovery_period_in_days = var.point_in_time_recovery.days
  }
}
