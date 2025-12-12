package dbx

import (
	"context"
	"errors"
	"heart/internal/awsx"
	"heart/internal/config"
	"heart/internal/models"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)

func GetWorkout(ctx context.Context, userId string, workoutId string) (*models.Workout, error) {
	pk := models.UserKey + userId
	sk := models.WorkoutKey + workoutId

	input := &dynamodb.GetItemInput{
		TableName: aws.String(config.App.WorkoutsTable),
		Key: map[string]types.AttributeValue{
			"PK": &types.AttributeValueMemberS{Value: pk},
			"SK": &types.AttributeValueMemberS{Value: sk},
		},
	}

	result, err := awsx.Db.GetItem(ctx, input)
	if err != nil {
		return nil, models.NewServerError(err)
	}

	if result.Item == nil {
		return nil, models.NewNotFoundError("Workout not found", nil)
	}

	var workout models.Workout
	err = attributevalue.UnmarshalMap(result.Item, &workout)
	if err != nil {
		return nil, models.NewServerError(err)
	}

	return &workout, nil
}

func SaveWorkout(ctx context.Context, in models.Workout) (*models.Workout, error) {
	item, err := attributevalue.MarshalMap(in)
	if err != nil {
		return nil, models.NewServerError(err)
	}

	input := &dynamodb.PutItemInput{
		TableName: aws.String(config.App.WorkoutsTable),
		Item:      item,
	}

	_, err = awsx.Db.PutItem(ctx, input)
	if err != nil {
		return nil, models.NewServerError(err)
	}

	return &in, nil
}

func DeleteWorkout(ctx context.Context, userId string, workoutId string) error {
	pk := models.UserKey + userId
	sk := models.WorkoutKey + workoutId

	input := &dynamodb.DeleteItemInput{
		TableName: aws.String(config.App.WorkoutsTable),
		Key: map[string]types.AttributeValue{
			"PK": &types.AttributeValueMemberS{Value: pk},
			"SK": &types.AttributeValueMemberS{Value: sk},
		},
	}

	_, err := awsx.Db.DeleteItem(ctx, input)

	if err != nil {
		var notFound *types.ConditionalCheckFailedException
		if ok := errors.As(err, &notFound); ok {
			return models.NewNotFoundError("Workout not found", notFound)
		}
		return models.NewServerError(err)
	}

	return nil
}

func GetWorkouts(ctx context.Context, userId string, limit int, cursor string) ([]models.Workout, string, error) {
	pk := models.UserKey + userId
	input := &dynamodb.QueryInput{
		TableName: aws.String(config.App.WorkoutsTable),
		ExpressionAttributeNames: map[string]string{
			"#PK": "PK",
			"#SK": "SK",
		},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":PK":     &types.AttributeValueMemberS{Value: pk},
			":SK_MIN": &types.AttributeValueMemberS{Value: "WORKOUT#"},
			":SK_MAX": &types.AttributeValueMemberS{Value: "WORKOUT$"}, // Using $ which comes after # in ASCII
		},
		KeyConditionExpression: aws.String("#PK = :PK AND #SK BETWEEN :SK_MIN AND :SK_MAX"),
		ScanIndexForward:       aws.Bool(false),
		Limit:                  aws.Int32(int32(limit)),
	}

	// pagination
	if cursor != "" {
		input.ExclusiveStartKey = map[string]types.AttributeValue{
			"PK": &types.AttributeValueMemberS{Value: pk},
			"SK": &types.AttributeValueMemberS{Value: models.WorkoutKey + cursor},
		}
	}

	result, err := awsx.Db.Query(ctx, input)
	if err != nil {
		return nil, "", models.NewServerError(err)
	}

	var workouts []models.Workout
	err = attributevalue.UnmarshalListOfMaps(result.Items, &workouts)
	if err != nil {
		return nil, "", models.NewServerError(err)
	}

	var nextCursor string
	if result.LastEvaluatedKey != nil {
		if skAttr, ok := result.LastEvaluatedKey["SK"]; ok {
			if skValue, ok := skAttr.(*types.AttributeValueMemberS); ok {
				nextCursor = strings.TrimPrefix(skValue.Value, "WORKOUT#")
			}
		}
	}

	return workouts, nextCursor, nil
}

func RemoveWorkoutImage(ctx context.Context, userId string, workoutId string) error {
	pk := models.UserKey + userId
	sk := models.WorkoutKey + workoutId

	input := &dynamodb.UpdateItemInput{
		TableName: aws.String(config.App.WorkoutsTable),
		Key: map[string]types.AttributeValue{
			"PK": &types.AttributeValueMemberS{Value: pk},
			"SK": &types.AttributeValueMemberS{Value: sk},
		},
		UpdateExpression: aws.String("REMOVE #image, #key"),
		ExpressionAttributeNames: map[string]string{
			"#image": "image",
			"#key":   "image_key",
		},
	}

	_, err := awsx.Db.UpdateItem(ctx, input)
	if err != nil {
		return models.NewServerError(err)
	}

	return nil
}

func GetWorkoutGallery(ctx context.Context, userId string, limit int, cursor string) ([]models.ProgressImage, *string, error) {
	pk := models.UserKey + userId

	input := &dynamodb.QueryInput{
		TableName: aws.String(config.App.WorkoutsTable),
		ExpressionAttributeNames: map[string]string{
			"#PK": "PK",
			"#SK": "SK",
		},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":PK":     &types.AttributeValueMemberS{Value: pk},
			":SK_MIN": &types.AttributeValueMemberS{Value: "PROGRESS#"},
			":SK_MAX": &types.AttributeValueMemberS{Value: "PROGRESS$"}, // '$' sorts after '#'
		},
		KeyConditionExpression: aws.String("#PK = :PK AND #SK BETWEEN :SK_MIN AND :SK_MAX"),
		ScanIndexForward:       aws.Bool(false), // most recent workoutId first
		Limit:                  aws.Int32(int32(limit)),
	}

	// pagination
	if cursor != "" {
		input.ExclusiveStartKey = map[string]types.AttributeValue{
			"PK": &types.AttributeValueMemberS{Value: pk},
			"SK": &types.AttributeValueMemberS{Value: "PROGRESS#" + cursor},
		}
	}

	result, err := awsx.Db.Query(ctx, input)
	if err != nil {
		return nil, nil, models.NewServerError(err)
	}

	var items []models.ProgressImage
	if err := attributevalue.UnmarshalListOfMaps(result.Items, &items); err != nil {
		return nil, nil, models.NewServerError(err)
	}

	var nextCursor *string
	if result.LastEvaluatedKey != nil {
		if skAttr, ok := result.LastEvaluatedKey["SK"]; ok {
			if skValue, ok := skAttr.(*types.AttributeValueMemberS); ok {
				cur := models.ProgressCursorFromSK(skValue.Value)
				nextCursor = &cur
			}
		}
	}

	return items, nextCursor, nil
}
