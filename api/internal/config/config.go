package config

import (
	"fmt"
	"os"
	"reflect"
	"strconv"
)

type DBConfig struct {
	DBHost     string `env:"DB_HOST" default:"localhost" required:"true"`
	DBPort     string `env:"DB_PORT" default:"5432" required:"true"`
	DBUser     string `env:"DB_USER" default:""`
	DBPassword string `env:"DB_PASSWORD" default:""`
	DBName     string `env:"DB_NAME" required:"true"`
	DBSSLMode  string `env:"DB_SSLMODE" default:"disable"   required:"true"`
	AppName    string `env:"APP_NAME" default:"heart-api"`
}

type SchedulerConfig struct {
	ScheduleGroup string `env:"SCHEDULE_GROUP" required:"true"`
}

type S3Config struct {
	UploadBucket string `env:"UPLOAD_BUCKET" required:"true"`
	MediaBucket  string `env:"MEDIA_BUCKET" required:"true"`
}

func (c *S3Config) UploadDestinationTag() string {
	return fmt.Sprintf(
		`<Tagging><TagSet><Tag><Key>destination</Key><Value>%s</Value></Tag></TagSet></Tagging>`,
		c.MediaBucket,
	)
}

func (c *S3Config) AvatarKey(userId string) string {
	return fmt.Sprintf("avatars/%s", userId)
}

type LambdaConfig struct {
	BackgroundFunctionArn  string `env:"BACKGROUND_FUNCTION" required:"true"`
	BackgroundFunctionRole string `env:"BACKGROUND_ROLE" required:"true"`
}

type SnsConfig struct {
	MonitoringTopic string `env:"MONITORING_TOPIC" required:"true"`
}

type AwsConfig struct {
	DynamoDBConfig
	LambdaConfig
	S3Config
	SchedulerConfig
	SnsConfig
	AwsRegion             string `env:"REGION" required:"true"`
	AccountDeletionOffset int    `env:"ACCOUNT_DELETION_OFFSET" default:"30" required:"true"`
}

type SentryConfig struct {
	SentryDSN string `env:"SENTRY_DSN"`
}

type FirebaseConfig struct {
	Credentials string `env:"FIREBASE_CREDENTIALS"`
}

type DynamoDBConfig struct {
	WorkoutsTable string `env:"WORKOUTS_TABLE" required:"true"`
}

type AppConfig struct {
	DBConfig
	AwsConfig
	SentryConfig
	FirebaseConfig
	CORSOrigins string `env:"CORS_ORIGINS" default:"*"` // Comma-separated list of allowed origins
}

func NewAppConfig() (*AppConfig, error) {
	cfg := &AppConfig{}
	if err := populate(cfg); err != nil {
		return nil, err
	}
	return cfg, nil
}

func NewFirebaseConfig() (config *FirebaseConfig, err error) {
	cfg := &FirebaseConfig{}
	if err := populate(cfg); err != nil {
		return nil, err
	}
	return cfg, nil
}

func fromEnv(v reflect.Value, t reflect.Type) error {
	for i := 0; i < v.NumField(); i++ {
		field := t.Field(i)
		fieldVal := v.Field(i)

		if field.Type.Kind() == reflect.Struct {
			if err := fromEnv(fieldVal, field.Type); err != nil {
				return err
			}
			continue
		}

		envKey := field.Tag.Get("env")
		defaultVal := field.Tag.Get("default")
		required := field.Tag.Get("required") == "true"

		envVal, found := os.LookupEnv(envKey)

		var finalVal string
		if found {
			finalVal = envVal
		} else if defaultVal != "" {
			finalVal = defaultVal
		} else if required {
			return fmt.Errorf("required env var %s not set", envKey)
		}

		switch field.Type.Kind() {
		case reflect.String:
			fieldVal.SetString(finalVal)
		case reflect.Int:
			intVal, err := strconv.Atoi(finalVal)
			if err != nil {
				return fmt.Errorf("invalid int for %s: %v", envKey, err)
			}
			fieldVal.SetInt(int64(intVal))
		default:
			return fmt.Errorf("unsupported config type: %s", field.Type.Kind())
		}
	}
	return nil
}

func populate(cfg any) error {
	v := reflect.ValueOf(cfg).Elem()
	t := v.Type()

	if err := fromEnv(v, t); err != nil {
		return err
	}
	return nil
}
