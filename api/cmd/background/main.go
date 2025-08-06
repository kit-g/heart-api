package main

import (
	"context"
	"errors"
	"fmt"
	"heart/internal/config"
	"heart/internal/firebasex"
	"heart/internal/models"
	"heart/internal/routerx"
	"log"

	"github.com/aws/aws-lambda-go/lambda"
)

func handler(ctx context.Context, event map[string]interface{}) (map[string]interface{}, error) {
	log.Printf("Received event: %+v", event)

	eventType, ok := event["Event"].(string)
	if !ok {
		return nil, models.NewValidationError(errors.New("missing Event field"))
	}

	switch eventType {
	case "AccountDeletion":
		payload, ok := event["Payload"].(map[string]interface{})
		if !ok {
			return nil, models.NewValidationError(errors.New("missing Payload field"))
		}

		userID, ok := payload["user_id"].(string)
		if !ok {
			return nil, models.NewValidationError(errors.New("missing user_id field"))
		}

		err := firebasex.DeleteUser(ctx, userID)
		if err != nil {
			return nil, models.NewServerError(err)
		}

		return map[string]interface{}{
			"statusCode": 200,
			"body":       fmt.Sprintf("Successfully deleted account for user %s", userID),
		}, nil
	default:
		return nil, models.NewValidationError(errors.New("invalid event type"))
	}
}

func initFirebase() error {
	cfg, err := config.NewFirebaseConfig()

	if err != nil {
		log.Fatal(err)
	}

	if cfg.Credentials != "" {
		if err := firebasex.Init(cfg.Credentials); err != nil {
			log.Printf("Failed to initialize Firebase client: %s", err)
			return err
		}
	}

	return nil
}

func main() {
	log.Printf("Starting Heart API Background - version: %s", routerx.String())
	err := initFirebase()
	if err != nil {
		return
	}

	lambda.Start(handler)
}
