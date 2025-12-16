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
	startAV, err := attributevalue.Marshal(in.Start)
	if err != nil {
		return nil, models.NewServerError(err)
	}
	exercisesAV, err := attributevalue.Marshal(in.Exercises)
	if err != nil {
		return nil, models.NewServerError(err)
	}

	input := &dynamodb.UpdateItemInput{
		TableName: aws.String(config.App.WorkoutsTable),
		Key: map[string]types.AttributeValue{
			"PK": &types.AttributeValueMemberS{Value: in.PK},
			"SK": &types.AttributeValueMemberS{Value: in.SK},
		},
		ExpressionAttributeNames: map[string]string{
			"#start":     "start",
			"#end":       "end",
			"#name":      "name",
			"#exercises": "exercises",
		},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":start":     startAV,
			":exercises": exercisesAV,
		},
		ConditionExpression: aws.String("attribute_exists(PK) AND attribute_exists(SK)"),
	}

	setParts := []string{
		"#start = :start",
		"#exercises = :exercises",
	}
	removeParts := []string{}

	if in.End != nil {
		endAV, err := attributevalue.Marshal(*in.End)
		if err != nil {
			return nil, models.NewServerError(err)
		}
		input.ExpressionAttributeValues[":end"] = endAV
		setParts = append(setParts, "#end = :end")
	} else {
		removeParts = append(removeParts, "#end")
	}

	if in.Name != "" {
		nameAV, err := attributevalue.Marshal(in.Name)
		if err != nil {
			return nil, models.NewServerError(err)
		}
		input.ExpressionAttributeValues[":name"] = nameAV
		setParts = append(setParts, "#name = :name")
	} else {
		removeParts = append(removeParts, "#name")
	}

	updateExpr := "SET " + strings.Join(setParts, ", ")
	if len(removeParts) > 0 {
		updateExpr += " REMOVE " + strings.Join(removeParts, ", ")
	}
	input.UpdateExpression = aws.String(updateExpr)

	_, err = awsx.Db.UpdateItem(ctx, input)
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

func RemoveWorkoutImage(ctx context.Context, userId, workoutId, imageId string) error {
	// imageId is actually the S3 object key (e.g. "workouts/<hash>/<uuidv7>.png")
	imageKey := strings.TrimPrefix(imageId, "/")

	if imageKey == "" {
		return models.NewValidationError(errors.New("missing image key"))
	}

	pk := models.UserKey + userId
	workoutSK := models.WorkoutKey + workoutId
	progressSK := models.ProgressKey + workoutId + "#" + imageKey

	tx := &dynamodb.TransactWriteItemsInput{
		TransactItems: []types.TransactWriteItem{
			{
				Update: &types.Update{
					TableName: aws.String(config.App.WorkoutsTable),
					Key: map[string]types.AttributeValue{
						"PK": &types.AttributeValueMemberS{Value: pk},
						"SK": &types.AttributeValueMemberS{Value: workoutSK},
					},
					UpdateExpression: aws.String("DELETE #images :imageset"),
					ExpressionAttributeNames: map[string]string{
						"#images": "images",
					},
					ExpressionAttributeValues: map[string]types.AttributeValue{
						":imageset": &types.AttributeValueMemberSS{Value: []string{imageKey}},
					},
					ConditionExpression: aws.String("attribute_exists(PK) AND attribute_exists(SK)"),
				},
			},
			{
				Delete: &types.Delete{
					TableName: aws.String(config.App.WorkoutsTable),
					Key: map[string]types.AttributeValue{
						"PK": &types.AttributeValueMemberS{Value: pk},
						"SK": &types.AttributeValueMemberS{Value: progressSK},
					},
				},
			},
		},
	}

	_, err := awsx.Db.TransactWriteItems(ctx, tx)
	if err != nil {
		var notFound *types.ConditionalCheckFailedException
		if ok := errors.As(err, &notFound); ok {
			return models.NewNotFoundError("Workout not found", notFound)
		}
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
			":PREFIX": &types.AttributeValueMemberS{Value: models.ProgressKey},
		},
		KeyConditionExpression: aws.String("#PK = :PK AND begins_with(#SK, :PREFIX)"),
		ScanIndexForward:       aws.Bool(false), // most recent workoutId first
		Limit:                  aws.Int32(int32(limit)),
	}

	// pagination
	if cursor != "" {
		input.ExclusiveStartKey = map[string]types.AttributeValue{
			"PK": &types.AttributeValueMemberS{Value: pk},
			"SK": &types.AttributeValueMemberS{Value: models.ProgressKey + cursor},
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
