package dbx

import (
	"context"
	"testing"

	"heart/internal/awsx"

	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
)

func TestGetTemplate_NotFound(t *testing.T) {
	teardown := setupTest(t)
	defer teardown()

	awsx.Db = &mockDynamo{
		GetItemFn: func(ctx context.Context, p *dynamodb.GetItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.GetItemOutput, error) {
			return &dynamodb.GetItemOutput{Item: nil}, nil
		},
	}

	_, err := GetTemplate(context.Background(), "u1", "t1")
	if err == nil {
		t.Fatalf("expected error")
	}
	// verify 404 status
	if s, ok := err.(interface{ Status() int }); !ok || s.Status() != 404 {
		t.Fatalf("expected 404 NotFound, got %#v", err)
	}
}
