package dbx

import (
	"context"
	"testing"

	"heart/internal/config"

	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
)

// mockDynamo implements awsx.DynamoDBAPI
type mockDynamo struct {
	GetItemFn            func(ctx context.Context, params *dynamodb.GetItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.GetItemOutput, error)
	PutItemFn            func(ctx context.Context, params *dynamodb.PutItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.PutItemOutput, error)
	UpdateItemFn         func(ctx context.Context, params *dynamodb.UpdateItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error)
	DeleteItemFn         func(ctx context.Context, params *dynamodb.DeleteItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.DeleteItemOutput, error)
	QueryFn              func(ctx context.Context, params *dynamodb.QueryInput, optFns ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error)
	TransactWriteItemsFn func(ctx context.Context, params *dynamodb.TransactWriteItemsInput, optFns ...func(*dynamodb.Options)) (*dynamodb.TransactWriteItemsOutput, error)
}

func (m *mockDynamo) GetItem(ctx context.Context, p *dynamodb.GetItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.GetItemOutput, error) {
	return m.GetItemFn(ctx, p, optFns...)
}

func (m *mockDynamo) PutItem(ctx context.Context, p *dynamodb.PutItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.PutItemOutput, error) {
	return m.PutItemFn(ctx, p, optFns...)
}

func (m *mockDynamo) UpdateItem(ctx context.Context, p *dynamodb.UpdateItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error) {
	return m.UpdateItemFn(ctx, p, optFns...)
}

func (m *mockDynamo) DeleteItem(ctx context.Context, p *dynamodb.DeleteItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.DeleteItemOutput, error) {
	return m.DeleteItemFn(ctx, p, optFns...)
}

func (m *mockDynamo) Query(ctx context.Context, p *dynamodb.QueryInput, optFns ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error) {
	return m.QueryFn(ctx, p, optFns...)
}

func (m *mockDynamo) TransactWriteItems(ctx context.Context, p *dynamodb.TransactWriteItemsInput, optFns ...func(*dynamodb.Options)) (*dynamodb.TransactWriteItemsOutput, error) {
	return m.TransactWriteItemsFn(ctx, p, optFns...)
}

func setupTest(t *testing.T) func() {
	t.Helper()
	config.App = &config.AppConfig{AwsConfig: config.AwsConfig{DynamoDBConfig: config.DynamoDBConfig{WorkoutsTable: "test-table"}}}
	return func() {
		// no-op for now
	}
}
