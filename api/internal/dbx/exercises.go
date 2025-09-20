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
	"unicode"

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
	if !isValidName(in.Name) {
		return nil, models.NewValidationError(fmt.Errorf("exercise name can only contain letters, numbers and spaces"))
	}

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

func EditExercise(ctx context.Context, userId string, exerciseName string, in models.EditExerciseIn) (*models.Exercise, error) {
	encodedName := url.PathEscape(exerciseName)

	var updateExpr []string
	exprAttrNames := map[string]string{
		"#PK": "PK",
		"#SK": "SK",
	}
	exprAttrValues := map[string]types.AttributeValue{}

	if in.Category != nil {
		exprAttrNames["#category"] = "category"
		exprAttrValues[":category"] = &types.AttributeValueMemberS{Value: *in.Category}
		updateExpr = append(updateExpr, "#category = :category")
	}

	if in.Target != nil {
		exprAttrNames["#target"] = "target"
		exprAttrValues[":target"] = &types.AttributeValueMemberS{Value: *in.Target}
		updateExpr = append(updateExpr, "#target = :target")
	}

	if in.Instructions != nil {
		exprAttrNames["#instructions"] = "instructions"
		if *in.Instructions == "" {
			updateExpr = append(updateExpr, "REMOVE #instructions")
		} else {
			exprAttrValues[":instructions"] = &types.AttributeValueMemberS{Value: *in.Instructions}
			updateExpr = append(updateExpr, "#instructions = :instructions")
		}
	}

	if in.Archived != nil {
		exprAttrNames["#archived"] = "archived"
		exprAttrValues[":archived"] = &types.AttributeValueMemberBOOL{Value: *in.Archived}
		updateExpr = append(updateExpr, "#archived = :archived")
	}

	if len(updateExpr) == 0 {
		return nil, models.NewValidationError(fmt.Errorf("no fields to update"))
	}

	update := strings.Join(updateExpr, ", ")

	if strings.Contains(update, "REMOVE #instructions") {
		// DynamoDB UpdateExpression cannot mix SET and REMOVE in a single clause without keywords; build properly
		var setParts []string
		for _, part := range updateExpr {
			if strings.HasPrefix(part, "#") && !strings.Contains(part, "instructions") {
				setParts = append(setParts, part)
			}
		}
		remove := ""
		if strings.Contains(strings.Join(updateExpr, " "), "REMOVE #instructions") {
			remove = " REMOVE #instructions"
		}
		if len(setParts) > 0 {
			update = "SET " + strings.Join(setParts, ", ") + remove
		} else {
			update = "REMOVE #instructions"
		}
	} else {
		update = "SET " + update
	}

	input := &dynamodb.UpdateItemInput{
		TableName:                 aws.String(config.App.WorkoutsTable),
		ConditionExpression:       aws.String("attribute_exists(#PK) AND attribute_exists(#SK)"),
		ExpressionAttributeNames:  exprAttrNames,
		ExpressionAttributeValues: exprAttrValues,
		Key: map[string]types.AttributeValue{
			"PK": &types.AttributeValueMemberS{Value: fmt.Sprintf("%s%s", models.UserKey, userId)},
			"SK": &types.AttributeValueMemberS{Value: fmt.Sprintf("%s%s", models.ExerciseKey, encodedName)},
		},
		UpdateExpression: aws.String(update),
		ReturnValues:     types.ReturnValueAllNew,
	}

	res, err := awsx.Db.UpdateItem(ctx, input)

	if err != nil {
		var checkFailed *types.ConditionalCheckFailedException
		if errors.As(err, &checkFailed) {
			return nil, models.NewValidationError(fmt.Errorf("exercise with name '%s' does not exist", exerciseName))
		}
		return nil, models.NewServerError(err)
	}

	var updated models.Exercise
	if err := attributevalue.UnmarshalMap(res.Attributes, &updated); err != nil {
		return nil, models.NewServerError(err)
	}

	// Trim name as in GetOwnExercises
	updated.Name = strings.TrimPrefix(updated.Name, "EXERCISE#")
	decodedName, err := url.PathUnescape(updated.Name)
	if err != nil {
		return nil, models.NewServerError(err)
	}
	updated.Name = decodedName
	return &updated, nil
}

// isValidName checks if the given string contains only letters, numbers, or spaces.
// Returns true if valid, otherwise false.
func isValidName(name string) bool {
	for _, r := range name {
		if !unicode.IsLetter(r) && !unicode.IsDigit(r) && !unicode.IsSpace(r) {
			return false
		}
	}
	return true
}
