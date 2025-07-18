package dbx

import (
	"context"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"heart/internal/awsx"
	"heart/internal/config"
	"heart/internal/models"
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
