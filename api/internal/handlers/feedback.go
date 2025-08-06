package handlers

import (
	"fmt"
	"heart/internal/awsx"
	"heart/internal/config"
	"heart/internal/models"
	"time"

	"github.com/gin-gonic/gin"
)

// LeaveFeedback godoc
//
// @Summary		Submit user feedback
// @Description	Allows users to submit feedback with a message and optionally attach a screenshot
// @Tags			feedback
// @Accept			json
// @Produce		json
// @Param			request	body		FeedbackRequest	true	"Feedback details"
// @Success		200		{object}	PresignedUrlResponse
// @Failure		400		{object}	ErrorResponse
// @Failure		401		{object}	ErrorResponse
// @Failure		500		{object}	ErrorResponse
// @Security		BearerAuth
// @Router			/feedback [post]
func LeaveFeedback(c *gin.Context, userId string) (any, error) {
	var request models.FeedbackRequest

	if err := c.BindJSON(&request); err != nil {
		return nil, models.NewValidationError(err)
	}

	key := fmt.Sprintf("feedback/%s/%s", userId, time.Now().Format("2006-01-02T15:04:05.999999-07:00"))

	link, err := awsx.GeneratePresignedPostURL(
		c.Request.Context(),
		config.App.MediaBucket,
		key,
		defaultMimeType,
		nil,
	)

	if err != nil {
		return nil, err
	}

	screenshotUrl := fmt.Sprintf("%s%s", link.URL, key)

	body := map[string]string{
		"user_id":    userId,
		"message":    request.Message,
		"screenshot": screenshotUrl,
	}

	err = awsx.SendToMonitoring(c.Request.Context(), body)

	if err != nil {
		return nil, err
	}

	return models.PresignedUrlResponse{
		URL:    link.URL,
		Fields: link.Values,
	}, nil
}
