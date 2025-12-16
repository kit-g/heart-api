package dbx

import (
	"context"
	"errors"
	"testing"
	"time"

	"heart/internal/awsx"
	"heart/internal/models"

	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/stretchr/testify/assert"
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

func TestGetWorkoutGallery_PaginationAndUnmarshal(t *testing.T) {
	teardown := setupTest(t)
	defer teardown()

	imageURL := "https://example.com/workouts/img.jpg?v=2025-12-11T20:41:16.797Z"
	imageKey := "workouts/abcd1234.jpg"

	progress := models.ProgressImage{
		PK:        "USER#u1",
		SK:        models.ProgressKey + "2025-07-25T18:20:01.253622Z#2025-12-11T20:41:16.797Z~deadbeef",
		WorkoutID: "2025-07-25T18:20:01.253622Z",
		PhotoID:   "2025-12-11T20:41:16.797Z~deadbeef",
		Image:     &imageURL,
		ImageKey:  &imageKey,
	}

	item, err := attributevalue.MarshalMap(progress)
	assert.NoError(t, err)

	cursorIn := "2025-07-01T00:00:00Z#2025-12-01T00:00:00Z~aaaa"
	nextSK := models.ProgressKey + "2025-06-01T00:00:00Z#2025-11-01T00:00:00Z~bbbb"

	awsx.Db = &mockDynamo{
		QueryFn: func(ctx context.Context, p *dynamodb.QueryInput, optFns ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error) {
			assert.NotNil(t, p.TableName)
			assert.NotEmpty(t, *p.TableName)

			assert.NotNil(t, p.ScanIndexForward)
			assert.False(t, *p.ScanIndexForward)

			assert.NotNil(t, p.Limit)
			assert.Equal(t, int32(20), *p.Limit)

			pkAttr, ok := p.ExpressionAttributeValues[":PK"].(*types.AttributeValueMemberS)
			assert.True(t, ok)
			assert.Equal(t, "USER#u1", pkAttr.Value)

			prefixAttr, ok := p.ExpressionAttributeValues[":PREFIX"].(*types.AttributeValueMemberS)
			assert.True(t, ok)
			assert.Equal(t, models.ProgressKey, prefixAttr.Value)

			assert.NotNil(t, p.KeyConditionExpression)
			assert.Equal(t, "#PK = :PK AND begins_with(#SK, :PREFIX)", *p.KeyConditionExpression)

			assert.NotNil(t, p.ExclusiveStartKey)

			exSk, ok := p.ExclusiveStartKey["SK"].(*types.AttributeValueMemberS)
			assert.True(t, ok)
			assert.Equal(t, models.ProgressKey+cursorIn, exSk.Value)

			return &dynamodb.QueryOutput{
				Items: []map[string]types.AttributeValue{item},
				LastEvaluatedKey: map[string]types.AttributeValue{
					"SK": &types.AttributeValueMemberS{Value: nextSK},
				},
			}, nil
		},
	}

	items, next, err := GetWorkoutGallery(context.Background(), "u1", 20, cursorIn)
	assert.NoError(t, err)

	assert.Len(t, items, 1)
	assert.Equal(t, "2025-07-25T18:20:01.253622Z", items[0].WorkoutID)
	assert.Equal(t, "2025-12-11T20:41:16.797Z~deadbeef", items[0].PhotoID)
	assert.NotNil(t, items[0].Image)
	assert.Equal(t, imageURL, *items[0].Image)

	assert.NotNil(t, next)
	assert.Equal(t, "2025-06-01T00:00:00Z#2025-11-01T00:00:00Z~bbbb", *next)
}

func TestGetWorkoutGallery_NoNextCursor(t *testing.T) {
	teardown := setupTest(t)
	defer teardown()

	awsx.Db = &mockDynamo{
		QueryFn: func(ctx context.Context, p *dynamodb.QueryInput, optFns ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error) {
			return &dynamodb.QueryOutput{
				Items:            []map[string]types.AttributeValue{},
				LastEvaluatedKey: nil,
			}, nil
		},
	}

	items, next, err := GetWorkoutGallery(context.Background(), "u1", 10, "")
	assert.NoError(t, err)
	assert.Len(t, items, 0)
	assert.Nil(t, next)
}

func TestGetWorkoutGallery_QueryErrorWrapped(t *testing.T) {
	teardown := setupTest(t)
	defer teardown()

	awsx.Db = &mockDynamo{
		QueryFn: func(ctx context.Context, p *dynamodb.QueryInput, optFns ...func(*dynamodb.Options)) (*dynamodb.QueryOutput, error) {
			return nil, errors.New("boom")
		},
	}

	_, _, err := GetWorkoutGallery(context.Background(), "u1", 10, "")
	assert.Error(t, err)

	var httpErr interface{ Status() int }
	assert.True(t, errors.As(err, &httpErr))
	assert.Equal(t, 500, httpErr.Status())
}
