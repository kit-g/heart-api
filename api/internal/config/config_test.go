package config

import (
	"os"
	"reflect"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// helper to set all required envs for NewAppConfig
func setMinimalAppEnv(t *testing.T) {
	t.Helper()
	// AWS + DynamoDB
	t.Setenv("REGION", "us-east-1")
	t.Setenv("WORKOUTS_TABLE", "workouts-table")
	// Lambda
	t.Setenv("BACKGROUND_FUNCTION", "arn:aws:lambda:us-east-1:123:function:fn")
	t.Setenv("BACKGROUND_ROLE", "arn:aws:iam::123:role/role")
	// S3
	t.Setenv("UPLOAD_BUCKET", "upload-bkt")
	t.Setenv("MEDIA_BUCKET", "media-bkt")
	// Scheduler
	t.Setenv("SCHEDULE_GROUP", "schedules")
	// SNS
	t.Setenv("MONITORING_TOPIC", "arn:aws:sns:us-east-1:123:topic")
	// leave ACCOUNT_DELETION_OFFSET unset to use default 30
	// leave Swagger and CORS unset to use defaults
}

func TestNewAppConfig_SuccessWithDefaults(t *testing.T) {
	setMinimalAppEnv(t)

	cfg, err := NewAppConfig()
	require.NoError(t, err)
	require.NotNil(t, cfg)

	// Requireds picked up
	assert.Equal(t, "us-east-1", cfg.AwsRegion)
	assert.Equal(t, "workouts-table", cfg.WorkoutsTable)
	assert.Equal(t, "arn:aws:lambda:us-east-1:123:function:fn", cfg.BackgroundFunctionArn)
	assert.Equal(t, "arn:aws:iam::123:role/role", cfg.BackgroundFunctionRole)
	assert.Equal(t, "upload-bkt", cfg.UploadBucket)
	assert.Equal(t, "media-bkt", cfg.MediaBucket)
	assert.Equal(t, "schedules", cfg.ScheduleGroup)
	assert.Equal(t, "arn:aws:sns:us-east-1:123:topic", cfg.MonitoringTopic)

	// Defaults
	assert.Equal(t, 30, cfg.AccountDeletionOffset)
	assert.Equal(t, "*", cfg.CORSOrigins)
	assert.Equal(t, "localhost:8080", cfg.SwaggerConfig.Host)
	assert.Equal(t, true, cfg.SwaggerConfig.DocsEnabled)
	assert.Equal(t, "", cfg.SwaggerConfig.BasePath)
}

func TestNewAppConfig_InvalidInt(t *testing.T) {
	setMinimalAppEnv(t)
	// override with bad int
	t.Setenv("ACCOUNT_DELETION_OFFSET", "not-an-int")

	cfg, err := NewAppConfig()
	assert.Nil(t, cfg)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "ACCOUNT_DELETION_OFFSET")
}

func TestFromEnv_RequiredMissing(t *testing.T) {
	// Don't set FOO to trigger required failure
	t.Setenv("FOO", "") // note: Setenv sets it. We must actually unset to test required missing.
	// t.Setenv doesn't allow unsetting, but we can clear from process after using it.
	_ = os.Unsetenv("FOO")

	type req struct {
		A string `env:"FOO" required:"true"`
	}
	var r req
	v := reflect.ValueOf(&r).Elem()
	typ := v.Type()
	err := fromEnv(v, typ)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "FOO")
}

func TestPopulate_InvalidBool(t *testing.T) {
	// use a small struct with a bool field
	type bcfg struct {
		Flag bool `env:"BOOL_FLAG"`
	}
	var c bcfg
	t.Setenv("BOOL_FLAG", "notabool")
	err := populate(&c)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "BOOL_FLAG")
}

func TestS3Helpers(t *testing.T) {
	c := S3Config{MediaBucket: "media-bkt"}
	// AvatarKey
	assert.Equal(t, "avatars/user-1", c.AvatarKey("user-1"))
	// UploadDestinationTag must embed the bucket
	tag := c.UploadDestinationTag()
	assert.Contains(t, tag, "destination")
	assert.Contains(t, tag, "media-bkt")
	assert.Contains(t, tag, "<Tagging>")
}

func TestNewFirebaseConfig(t *testing.T) {
	// Set creds
	t.Setenv("FIREBASE_CREDENTIALS", "{json}")
	cfg, err := NewFirebaseConfig()
	require.NoError(t, err)
	assert.Equal(t, "{json}", cfg.Credentials)

	// Unset creds -> should still succeed with empty string
	_ = os.Unsetenv("FIREBASE_CREDENTIALS")
	cfg2, err2 := NewFirebaseConfig()
	require.NoError(t, err2)
	assert.Equal(t, "", cfg2.Credentials)
}
