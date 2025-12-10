package awsx

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	env "heart/internal/config"
	"html"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/scheduler"
	"github.com/aws/aws-sdk-go-v2/service/scheduler/types"
	"github.com/aws/aws-sdk-go-v2/service/sns"
)

type DynamoDbAPI interface {
	GetItem(ctx context.Context, params *dynamodb.GetItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.GetItemOutput, error)
	PutItem(ctx context.Context, params *dynamodb.PutItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.PutItemOutput, error)
	UpdateItem(ctx context.Context, params *dynamodb.UpdateItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error)
	DeleteItem(ctx context.Context, params *dynamodb.DeleteItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.DeleteItemOutput, error)
	Query(ctx context.Context, params *dynamodb.QueryInput, optFns ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error)
}

var (
	Db       DynamoDbAPI
	Env      env.AwsConfig
	events   *scheduler.Client
	S3       *s3.Client
	s3Signer *s3.PresignClient
	SNS      *sns.Client
)

func Init(ctx context.Context, c env.AwsConfig) error {
	Env = c
	cfg, err := config.LoadDefaultConfig(
		ctx,
		config.WithRegion(c.AwsRegion),
	)

	if err != nil {
		return fmt.Errorf("failed to create AWS session: %w", err)
	}

	events = scheduler.NewFromConfig(cfg)
	S3 = s3.NewFromConfig(cfg)
	s3Signer = s3.NewPresignClient(S3)
	SNS = sns.NewFromConfig(cfg)
	Db = dynamodb.NewFromConfig(cfg)
	return nil
}

func GeneratePresignedPostURL(
	ctx context.Context,
	bucket string,
	key string,
	contentType string,
	tagging *map[string]string,
) (*s3.PresignedPostRequest, error) {
	input := s3.PutObjectInput{
		Bucket:      aws.String(bucket),
		Key:         aws.String(key),
		ContentType: aws.String(contentType),
	}

	var tagset string
	request, err := s3Signer.PresignPostObject(
		ctx,
		&input,
		func(options *s3.PresignPostOptions) {
			options.Expires = 15 * time.Minute

			conditions := make([]interface{}, 0, 3)
			conditions = append(conditions,
				[]interface{}{"content-length-range", minContentLength, maxContentLength},
				map[string]string{"Content-Type": contentType},
			)

			if tagging != nil {
				tagset = buildTags(*tagging)
				conditions = append(conditions, map[string]string{"tagging": tagset})
			}

			options.Conditions = conditions
		},
	)

	if err != nil {
		return nil, fmt.Errorf("failed to sign request: %w", err)
	}

	if request.Values == nil {
		request.Values = make(map[string]string)
	}

	if tagging != nil {
		request.Values["tagging"] = tagset
	}

	request.Values["Content-Type"] = contentType

	return request, nil
}

func buildTags(tags map[string]string) string {
	var b strings.Builder
	b.WriteString("<Tagging><TagSet>")
	for k, v := range tags {
		b.WriteString("<Tag><Key>")
		b.WriteString(html.EscapeString(k))
		b.WriteString("</Key><Value>")
		b.WriteString(html.EscapeString(v))
		b.WriteString("</Value></Tag>")
	}
	b.WriteString("</TagSet></Tagging>")
	return b.String()
}

func DeleteObject(ctx context.Context, bucket string, key string) (*s3.DeleteObjectOutput, error) {
	options := s3.DeleteObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(key),
	}
	return S3.DeleteObject(ctx, &options)
}

func CreateAccountDeletionSchedule(ctx context.Context, userId string) (*time.Time, *string, error) {
	scheduleName := fmt.Sprintf("account-deletion-%s", userId)
	when := time.Now().UTC().AddDate(0, 0, Env.AccountDeletionOffset)
	desc := fmt.Sprintf("Deletes user %s account after %d days", userId, Env.AccountDeletionOffset)

	payload, err := json.Marshal(
		map[string]any{
			"Event": "AccountDeletion",
			"Payload": map[string]string{
				"user_id": userId,
			},
		},
	)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to marshal input payload: %w", err)
	}

	input := scheduler.CreateScheduleInput{
		ActionAfterCompletion: types.ActionAfterCompletionDelete,
		Description:           aws.String(desc),
		FlexibleTimeWindow: &types.FlexibleTimeWindow{
			Mode: types.FlexibleTimeWindowModeOff,
		},
		GroupName:          aws.String(Env.ScheduleGroup),
		Name:               aws.String(scheduleName),
		ScheduleExpression: aws.String(fmt.Sprintf("at(%s)", when.Format("2006-01-02T15:04:05"))),
		State:              types.ScheduleStateEnabled,
		Target: &types.Target{
			Arn:     aws.String(Env.BackgroundFunctionArn),
			Input:   aws.String(string(payload)),
			RoleArn: aws.String(Env.BackgroundFunctionRole),
		},
	}
	out, err := events.CreateSchedule(ctx, &input)

	if err != nil {
		var conflictErr *types.ConflictException
		if errors.As(err, &conflictErr) {
			// schedule already exists, ok
			return &when, nil, nil
		}
		return nil, nil, fmt.Errorf("failed to create schedule: %w", err)
	}

	return &when, out.ScheduleArn, nil
}

func DeleteAccountDeletionSchedule(ctx context.Context, scheduleArn *string) error {
	if scheduleArn == nil {
		return nil
	}

	parts := strings.Split(*scheduleArn, "/")
	scheduleName := parts[len(parts)-1]

	in := scheduler.DeleteScheduleInput{
		Name:      aws.String(scheduleName),
		GroupName: aws.String(Env.ScheduleGroup),
	}
	_, err := events.DeleteSchedule(ctx, &in)

	if err != nil {
		var notFound *types.ResourceNotFoundException
		if errors.As(err, &notFound) {
			// schedule already exists, ok
			return nil
		}
	}

	return err
}

func sendSnsMessage(ctx context.Context, topicArn string, message any) error {
	var m string

	switch v := message.(type) {
	case string:
		m = v
	default:
		marshal, err := json.Marshal(v)
		if err != nil {
			return fmt.Errorf("failed to marshal message: %w", err)
		}
		m = string(marshal)
	}

	defaults := map[string]string{
		"default": m,
	}

	wrapped, err := json.Marshal(defaults)

	if err != nil {
		return fmt.Errorf("failed to marshal message: %w", err)
	}

	input := sns.PublishInput{
		Message:          aws.String(string(wrapped)),
		MessageStructure: aws.String("json"),
		TopicArn:         aws.String(topicArn),
	}

	_, err = SNS.Publish(ctx, &input)

	if err != nil {
		return fmt.Errorf("failed to send SNS message: %w", err)
	}

	return nil
}

func SendToMonitoring(ctx context.Context, message any) error {
	return sendSnsMessage(ctx, Env.MonitoringTopic, message)
}

const (
	minContentLength = 128
	maxContentLength = 31_457_280 // 30 MB max
)
