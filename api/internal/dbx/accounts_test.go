package dbx

import (
	"context"
	"testing"

	"heart/internal/awsx"
	"heart/internal/models"

	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)

func TestSaveAccount_SetsAvatarNullWhenNil(t *testing.T) {
	teardown := setupTest(t)
	defer teardown()

	var captured *dynamodb.UpdateItemInput

	// Prepare output attributes to unmarshal back into user
	username := "Jane"
	respUser := models.UserInternal{
		PK:          models.UserKey + "u1",
		SK:          models.UserKey + "u1",
		Username:    &username,
		Email:       "jane@example.com",
		FirebaseUID: "u1",
		AvatarUrl:   nil,
	}
	attrs, err := attributevalue.MarshalMap(respUser)
	if err != nil {
		t.Fatalf("marshal err: %v", err)
	}

	awsx.Db = &mockDynamo{
		UpdateItemFn: func(ctx context.Context, p *dynamodb.UpdateItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error) {
			captured = p
			return &dynamodb.UpdateItemOutput{Attributes: attrs}, nil
		},
	}

	var in models.User
	in.Email = "jane@example.com"
	in.Username = &username
	in.FirebaseUID = "" // will be set by SaveAccount
	in.AvatarUrl = nil

	out, err := SaveAccount(context.Background(), "u1", in)
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if out.AvatarUrl != nil {
		t.Fatalf("expected nil avatar in output")
	}
	if captured == nil {
		t.Fatalf("expected UpdateItem to be called")
	}
	av, ok := captured.ExpressionAttributeValues[":avatar"].(*types.AttributeValueMemberNULL)
	if !ok || !av.Value {
		t.Fatalf("expected :avatar to be NULL, got %#v", captured.ExpressionAttributeValues[":avatar"])
	}
}

func TestSaveAccount_SetsAvatarStringWhenProvided(t *testing.T) {
	teardown := setupTest(t)
	defer teardown()

	var captured *dynamodb.UpdateItemInput
	username := "Jane"
	avatar := "https://example.com/a.png"
	respUser := models.UserInternal{
		PK:          models.UserKey + "u1",
		SK:          models.UserKey + "u1",
		Username:    &username,
		Email:       "jane@example.com",
		FirebaseUID: "u1",
		AvatarUrl:   &avatar,
	}
	attrs, err := attributevalue.MarshalMap(respUser)
	if err != nil {
		t.Fatalf("marshal err: %v", err)
	}

	awsx.Db = &mockDynamo{
		UpdateItemFn: func(ctx context.Context, p *dynamodb.UpdateItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error) {
			captured = p
			return &dynamodb.UpdateItemOutput{Attributes: attrs}, nil
		},
	}

	var in models.User
	in.Email = "jane@example.com"
	in.Username = &username
	in.AvatarUrl = &avatar

	out, err := SaveAccount(context.Background(), "u1", in)
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if out.AvatarUrl == nil || *out.AvatarUrl != avatar {
		t.Fatalf("expected avatar %s in output", avatar)
	}
	if captured == nil {
		t.Fatalf("expected UpdateItem to be called")
	}
	if _, ok := captured.ExpressionAttributeValues[":avatar"].(*types.AttributeValueMemberS); !ok {
		t.Fatalf("expected :avatar to be String, got %#v", captured.ExpressionAttributeValues[":avatar"])
	}
}
