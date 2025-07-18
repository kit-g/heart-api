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

func GetTemplates(ctx context.Context, userId string) ([]models.Template, error) {
	pk := "USER#" + userId
	input := &dynamodb.QueryInput{
		TableName: aws.String(config.App.WorkoutsTable),
		ExpressionAttributeNames: map[string]string{
			"#PK": "PK",
			"#SK": "SK",
		},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":PK":     &types.AttributeValueMemberS{Value: pk},
			":PREFIX": &types.AttributeValueMemberS{Value: "TEMPLATE"},
		},
		KeyConditionExpression: aws.String("#PK = :PK AND begins_with( #SK , :PREFIX )"),
	}

	result, err := awsx.Db.Query(ctx, input)
	if err != nil {
		return nil, models.NewServerError(err)
	}

	var templates []models.Template
	err = attributevalue.UnmarshalListOfMaps(result.Items, &templates)
	if err != nil {
		return nil, models.NewServerError(err)
	}

	return templates, nil
}

func GetTemplate(ctx context.Context, userId string, templateId string) (*models.Template, error) {
	pk := "USER#" + userId
	sk := "TEMPLATE#" + templateId

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
		return nil, models.NewNotFoundError("Template not found", nil)
	}

	var template models.Template
	err = attributevalue.UnmarshalMap(result.Item, &template)
	if err != nil {
		return nil, models.NewServerError(err)
	}

	return &template, nil
}

func SaveTemplate(ctx context.Context, in models.Template) (*models.Template, error) {
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

func DeleteTemplate(ctx context.Context, userId string, templateId string) error {
	pk := "USER#" + userId
	sk := "TEMPLATE#" + templateId

	input := &dynamodb.DeleteItemInput{
		TableName: aws.String(config.App.WorkoutsTable),
		Key: map[string]types.AttributeValue{
			"PK": &types.AttributeValueMemberS{Value: pk},
			"SK": &types.AttributeValueMemberS{Value: sk},
		},
	}

	_, err := awsx.Db.DeleteItem(ctx, input)
	if err != nil {
		return models.NewServerError(err)
	}

	return nil
}
