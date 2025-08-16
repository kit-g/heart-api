package dbx

import (
	"context"
	"testing"

	"heart/internal/awsx"

	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)

type exercise struct {
	PK   string `dynamodbav:"PK"`
	SK   string `dynamodbav:"SK"`
	Name string `dynamodbav:"name"`
}

func TestGetExercises(t *testing.T) {
	teardown := setupTest(t)
	defer teardown()

	m1, _ := attributevalue.MarshalMap(exercise{PK: "EXERCISE", SK: "EXERCISE#PushUp", Name: "PushUp"})
	m2, _ := attributevalue.MarshalMap(exercise{PK: "EXERCISE", SK: "EXERCISE#PullUp", Name: "PullUp"})

	awsx.Db = &mockDynamo{
		QueryFn: func(ctx context.Context, p *dynamodb.QueryInput, optFns ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error) {
			return &dynamodb.QueryOutput{Items: []map[string]types.AttributeValue{m1, m2}}, nil
		},
	}

	list, err := GetExercises(context.Background())
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if len(list) != 2 {
		t.Fatalf("expected 2 exercises, got %d", len(list))
	}
}
