package dbx

import (
	"context"
	"errors"
	"fmt"
	"heart/internal/awsx"
	"heart/internal/config"
	"heart/internal/models"
	"net/url"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)

func GetExercises(ctx context.Context) ([]models.Exercise, error) {
	input := &dynamodb.QueryInput{
		TableName:              aws.String(config.App.WorkoutsTable),
		KeyConditionExpression: aws.String("PK = :PK"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":PK": &types.AttributeValueMemberS{Value: "EXERCISE"},
		},
	}

	result, err := awsx.Db.Query(ctx, input)
	if err != nil {
		return nil, models.NewServerError(err)
	}

	var exercises []models.Exercise
	err = attributevalue.UnmarshalListOfMaps(result.Items, &exercises)
	if err != nil {
		return nil, models.NewServerError(err)
	}

	return exercises, nil
}

func MakeExercise(ctx context.Context, in models.UserExerciseIn, userId string) (*models.UserExerciseIn, error) {
	exercise := models.NewUserExercise(&in, userId)
	item, err := attributevalue.MarshalMap(exercise)
	if err != nil {
		return nil, models.NewServerError(err)
	}

	input := &dynamodb.PutItemInput{
		TableName:           aws.String(config.App.WorkoutsTable),
		ConditionExpression: aws.String("attribute_not_exists(#PK) AND attribute_not_exists(#SK)"),
		ExpressionAttributeNames: map[string]string{
			"#PK": "PK",
			"#SK": "SK",
		},
		Item: item,
	}

	_, err = awsx.Db.PutItem(ctx, input)
	if err != nil {
		var checkFailed *types.ConditionalCheckFailedException
		if errors.As(err, &checkFailed) {
			return nil, models.NewValidationError(fmt.Errorf("exercise with name '%s' already exists", in.Name))
		}
		return nil, models.NewServerError(err)
	}

	return &in, nil
}

func GetOwnExercises(ctx context.Context, userId string) ([]models.Exercise, error) {
	input := &dynamodb.QueryInput{
		TableName:              aws.String(config.App.WorkoutsTable),
		KeyConditionExpression: aws.String("#PK = :PK AND begins_with(#SK, :SK)"),
		ExpressionAttributeNames: map[string]string{
			"#PK": "PK",
			"#SK": "SK",
		},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":PK": &types.AttributeValueMemberS{Value: fmt.Sprintf("%s%s", models.UserKey, userId)},
			":SK": &types.AttributeValueMemberS{Value: models.ExerciseKey},
		},
	}

	result, err := awsx.Db.Query(ctx, input)
	if err != nil {
		return nil, models.NewServerError(err)
	}

	var exercises []models.Exercise
	err = attributevalue.UnmarshalListOfMaps(result.Items, &exercises)
	if err != nil {
		return nil, models.NewServerError(err)
	}

	for i := range exercises {
		exercises[i].Name = strings.TrimPrefix(exercises[i].Name, "EXERCISE#")
		decodedName, err := url.QueryUnescape(exercises[i].Name)
		if err != nil {
			return nil, models.NewServerError(err)
		}
		exercises[i].Name = decodedName
	}

	return exercises, nil
}
