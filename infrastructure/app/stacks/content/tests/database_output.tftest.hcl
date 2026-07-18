# Tests for the `database` output's hand-built connection strings.
#
# The output normally depends on a live S3 secret (data.aws_s3_object) and a
# real Supabase project. We mock both providers and override just those two
# values, so the test exercises the string interpolation with zero real infra.
#
# Run:  AWS_PROFILE=heart-dev terraform init && terraform test
# (mock providers mean no real AWS/Supabase calls are made)

mock_provider "aws" {}
mock_provider "supabase" {}

variables {
  region     = "ca-central-1"
  account_id = "583168578067"
  supabase_project = {
    name = "heart-dev"
  }
}

# apply (not plan) so the overridden project id is a known value the output
# strings can interpolate. With both providers mocked, apply touches nothing real.
run "connection_strings_are_built_from_the_secret" {
  command = apply

  # Stub the S3 secret body the stack jsondecodes.
  override_data {
    target = data.aws_s3_object.supabase_secret
    values = {
      body = "{\"org_id\":\"org_123\",\"password\":\"s3cr3t\",\"region\":\"ca-central-1\"}"
    }
  }

  # Pin the Supabase project id so the output is deterministic.
  override_resource {
    target = supabase_project.heart
    values = {
      id = "abcdefghijklmnop"
    }
  }

  assert {
    condition     = output.database.database == "heart"
    error_message = "Database name should be the hard-coded 'heart'"
  }

  assert {
    condition     = output.database.port == 5432
    error_message = "Pooler port should be 5432"
  }

  assert {
    condition     = output.database.user == "postgres.abcdefghijklmnop"
    error_message = "User should be postgres.<project id>"
  }

  # The full pooler connection string — note it uses the aws-0- prefix and
  # port 6543 (transaction pooler), independent of local.pooler_port (5432).
  assert {
    condition     = output.database.connection == "postgres://postgres.abcdefghijklmnop:s3cr3t@aws-0-ca-central-1.pooler.supabase.com:6543/heart"
    error_message = "Connection string does not match expected pooler URL"
  }

  # The `host` output uses aws-1- (not aws-0- like `connection` above).
  # This test PINS that current behavior so the mismatch can't drift silently.
  # If the two are supposed to agree, one of them is a bug — decide, then update.
  assert {
    condition     = output.database.host == "aws-1-ca-central-1.pooler.supabase.com"
    error_message = "Host does not match expected pooler hostname"
  }
}
