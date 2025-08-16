package dbx

import (
	"context"
	"errors"
	"testing"
	"time"

	"heart/internal/awsx"

	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)

func TestGetWorkouts_PaginationAndUnmarshal(t *testing.T) {
	teardown := setupTest(t)
	defer teardown()

	// Prepare one workout item
	now := time.Now().UTC()
	w := struct {
		PK    string    `dynamodbav:"PK"`
		SK    string    `dynamodbav:"SK"`
		Name  string    `dynamodbav:"name"`
		Start time.Time `dynamodbav:"start"`
	}{
		PK:    "USER#u1",
		SK:    "WORKOUT#w1",
		Name:  "Legs",
		Start: now,
	}
	var err error
	item, err := attributevalue.MarshalMap(w)
	if err != nil {
		t.Fatalf("marshal err: %v", err)
	}

	awsx.Db = &mockDynamo{
		QueryFn: func(ctx context.Context, p *dynamodb.QueryInput, optFns ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error) {
			// verify table name and key expression basics
			if p.TableName == nil || *p.TableName == "" {
				t.Fatalf("expected table name")
			}
			return &dynamodb.QueryOutput{
				Items: []map[string]types.AttributeValue{item},
				LastEvaluatedKey: map[string]types.AttributeValue{
					"SK": &types.AttributeValueMemberS{Value: "WORKOUT#next"},
				},
			}, nil
		},
	}

	workouts, cursor, err := GetWorkouts(context.Background(), "u1", 10, "")
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if cursor != "next" {
		t.Fatalf("expected cursor 'next', got %q", cursor)
	}
	if len(workouts) != 1 {
		t.Fatalf("expected 1 workout, got %d", len(workouts))
	}
	if workouts[0].Name != "Legs" {
		t.Fatalf("unexpected workout name: %s", workouts[0].Name)
	}
}

func TestDeleteWorkout_NotFoundMapsToNotFoundError(t *testing.T) {
	teardown := setupTest(t)
	defer teardown()

	awsx.Db = &mockDynamo{
		DeleteItemFn: func(ctx context.Context, p *dynamodb.DeleteItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.DeleteItemOutput, error) {
			return nil, &types.ConditionalCheckFailedException{}
		},
	}

	err := DeleteWorkout(context.Background(), "u1", "w1")
	if err == nil {
		t.Fatalf("expected error")
	}
	var notFound interface{ Status() int }
	if !errors.As(err, &notFound) || notFound.Status() != 404 {
		t.Fatalf("expected NotFound error with 404, got: %#v", err)
	}
}
