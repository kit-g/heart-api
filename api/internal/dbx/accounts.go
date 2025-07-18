package dbx

import (
	"context"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"heart/internal/awsx"
	"heart/internal/config"
	"heart/internal/models"
	"strconv"
)

func SaveAccount(ctx context.Context, userId string, in models.User) (*models.User, error) {
	in.FirebaseUID = userId
	internal := models.NewUserInternal(&in)

	input := &dynamodb.UpdateItemInput{
		TableName: aws.String(config.App.WorkoutsTable),
		Key: map[string]types.AttributeValue{
			"PK": &types.AttributeValueMemberS{Value: internal.PK},
			"SK": &types.AttributeValueMemberS{Value: internal.PK},
		},
		UpdateExpression: aws.String("SET #username = :username, #email = :email, #avatar = :avatar, #firebase_uid = :firebase_uid"),
		ExpressionAttributeNames: map[string]string{
			"#username":     "username",
			"#email":        "email",
			"#avatar":       "avatar",
			"#firebase_uid": "firebase_uid",
		},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":username":     &types.AttributeValueMemberS{Value: internal.Username},
			":email":        &types.AttributeValueMemberS{Value: internal.Email},
			":firebase_uid": &types.AttributeValueMemberS{Value: internal.FirebaseUID},
		},
		ReturnValues: types.ReturnValueAllNew,
	}

	var avatar types.AttributeValue

	if internal.AvatarUrl == nil {
		avatar = &types.AttributeValueMemberNULL{Value: true}
	} else {
		avatar = &types.AttributeValueMemberS{Value: *internal.AvatarUrl}
	}

	input.ExpressionAttributeValues[":avatar"] = avatar

	response, err := awsx.Db.UpdateItem(ctx, input)

	if err != nil {
		return nil, models.NewServerError(err)
	}

	var out models.UserInternal
	err = attributevalue.UnmarshalMap(response.Attributes, &out)
	if err != nil {
		return nil, models.NewServerError(err)
	}

	user := models.NewUser(&out)

	return &user, nil
}

func GetAccount(ctx context.Context, userId string) (*models.User, error) {
	pk := models.UserKey + userId
	input := &dynamodb.GetItemInput{
		TableName: aws.String(config.App.WorkoutsTable),
		Key: map[string]types.AttributeValue{
			"PK": &types.AttributeValueMemberS{Value: pk},
			"SK": &types.AttributeValueMemberS{Value: pk},
		},
	}

	response, err := awsx.Db.GetItem(ctx, input)
	if err != nil {
		return nil, models.NewServerError(err)
	}

	if response.Item == nil {
		return nil, nil // handled down the line
	}

	var out models.UserInternal
	err = attributevalue.UnmarshalMap(response.Item, &out)
	if err != nil {
		return nil, models.NewServerError(err)
	}
	user := models.NewUser(&out)

	return &user, nil
}

func ScheduleAccountForDeletion(ctx context.Context, userId string, scheduleArn string, when int64) error {
	pk := models.UserKey + userId
	input := &dynamodb.UpdateItemInput{
		TableName: aws.String(config.App.WorkoutsTable),
		Key: map[string]types.AttributeValue{
			"PK": &types.AttributeValueMemberS{Value: pk},
			"SK": &types.AttributeValueMemberS{Value: pk},
		},
		ConditionExpression: aws.String("attribute_exists(PK) AND attribute_exists(SK)"),
		UpdateExpression:    aws.String("SET account_deletion_schedule = :schedule, scheduled_for_deletion_at = :scheduled_for_deletion_at"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":schedule": &types.AttributeValueMemberS{Value: scheduleArn},
			":scheduled_for_deletion_at": &types.AttributeValueMemberN{
				Value: strconv.FormatInt(when, 10), // must be string, even though it's a number type
			},
		},
		ReturnValues: types.ReturnValueNone,
	}

	_, err := awsx.Db.UpdateItem(ctx, input)
	if err != nil {
		return models.NewServerError(fmt.Errorf("failed to schedule account deletion: %w", err))
	}

	return nil
}

func UndoAccountDeletion(ctx context.Context, userId string) error {
	pk := models.UserKey + userId
	input := &dynamodb.UpdateItemInput{
		TableName: aws.String(config.App.WorkoutsTable),
		Key: map[string]types.AttributeValue{
			"PK": &types.AttributeValueMemberS{Value: pk},
			"SK": &types.AttributeValueMemberS{Value: pk},
		},
		ConditionExpression: aws.String("attribute_exists(PK) AND attribute_exists(SK)"),
		UpdateExpression:    aws.String("REMOVE account_deletion_schedule, scheduled_for_deletion_at"),
	}
	_, err := awsx.Db.UpdateItem(ctx, input)
	if err != nil {
		return models.NewServerError(fmt.Errorf("failed to undo account deletion: %w", err))
	}
	return nil
}

func RemoveAvatar(ctx context.Context, userId string) error {
	pk := models.UserKey + userId
	input := &dynamodb.UpdateItemInput{
		TableName: aws.String(config.App.WorkoutsTable),
		Key: map[string]types.AttributeValue{
			"PK": &types.AttributeValueMemberS{Value: pk},
			"SK": &types.AttributeValueMemberS{Value: pk},
		},
		ConditionExpression: aws.String("attribute_exists(PK) AND attribute_exists(SK)"),
		UpdateExpression:    aws.String("REMOVE avatar"),
	}
	_, err := awsx.Db.UpdateItem(ctx, input)
	if err != nil {
		return models.NewServerError(fmt.Errorf("failed to remove avatar: %w", err))
	}
	return nil
}
