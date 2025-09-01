package dbx

import (
	"context"
	"errors"
	"heart/internal/models"
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

func TestMakeExercise_Success(t *testing.T) {
	teardown := setupTest(t)
	defer teardown()

	awsx.Db = &mockDynamo{
		PutItemFn: func(ctx context.Context, p *dynamodb.PutItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.PutItemOutput, error) {
			// simulate successful put
			return &dynamodb.PutItemOutput{}, nil
		},
	}

	in := models.UserExerciseIn{Name: "Push Up", Category: "Body", Target: "Chest"}
	res, err := MakeExercise(context.Background(), in, "user-1")
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if res == nil || res.Name != in.Name {
		t.Fatalf("unexpected result: %#v", res)
	}
}

func TestMakeExercise_AlreadyExists(t *testing.T) {
	teardown := setupTest(t)
	defer teardown()

	awsx.Db = &mockDynamo{
		PutItemFn: func(ctx context.Context, p *dynamodb.PutItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.PutItemOutput, error) {
			return nil, &types.ConditionalCheckFailedException{}
		},
	}

	_, err := MakeExercise(context.Background(), models.UserExerciseIn{Name: "Push Up", Category: "Body", Target: "Chest"}, "user-1")
	if err == nil {
		t.Fatalf("expected error, got nil")
	}
}

func TestMakeExercise_ServerError(t *testing.T) {
	teardown := setupTest(t)
	defer teardown()

	awsx.Db = &mockDynamo{
		PutItemFn: func(ctx context.Context, p *dynamodb.PutItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.PutItemOutput, error) {
			return nil, errors.New("boom")
		},
	}

	_, err := MakeExercise(context.Background(), models.UserExerciseIn{Name: "Push Up", Category: "Body", Target: "Chest"}, "user-1")
	if err == nil {
		t.Fatalf("expected error, got nil")
	}
}
