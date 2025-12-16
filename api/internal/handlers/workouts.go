package handlers

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"heart/internal/awsx"
	"heart/internal/config"
	"heart/internal/dbx"
	"heart/internal/models"
	"maps"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// test seams for dbx dependencies
var (
	dbGetWorkouts       = dbx.GetWorkouts
	dbGetWorkout        = dbx.GetWorkout
	dbDeleteWorkout     = dbx.DeleteWorkout
	removeWorkoutImage  = dbx.RemoveWorkoutImage
	dbGetWorkoutGallery = dbx.GetWorkoutGallery
)

// GetWorkouts godoc
//
//	@Summary		Returns user workouts
//	@Description	Returns paginated list of user workouts with exercises and sets
//	@Tags			workouts
//	@Accept			json
//	@Produce		json
//	@ID				getWorkouts
//	@Param			X-App-Version	header		string	false	"Client app version"
//	@Param			pageSize		query		integer	false	"Page size for pagination"
//	@Param			cursor			query		string	false	"Cursor for pagination"
//	@Success		200				{object}	WorkoutResponse
//	@Failure		401				{object}	ErrorResponse	"Unauthorized"
//	@Failure		500				{object}	ErrorResponse	"Server error"
//	@Router			/workouts [get]
//	@Security		BearerAuth
func GetWorkouts(c *gin.Context, userId string) (any, error) {
	pageSize := 10
	if size := c.Query("pageSize"); size != "" {
		if parsed, err := strconv.Atoi(size); err == nil && parsed > 0 {
			pageSize = parsed
		}
	}

	cursor := c.Query("cursor")

	workouts, last, err := dbGetWorkouts(c.Request.Context(), userId, pageSize, cursor)

	if err != nil {
		return nil, models.NewServerError(err)
	}

	return models.WorkoutResponse{
		Workouts: models.NewWorkoutsArray(workouts, config.App.MediaDistributionAlias),
		Cursor:   last,
	}, nil
}

// GetWorkout godoc
//
//	@Summary		Returns a workout
//	@Description	Returns a single workout by ID with exercises and sets
//	@Tags			workouts
//	@Accept			json
//	@Produce		json
//	@ID				getWorkout
//	@Param			X-App-Version	header		string	false	"Client app version"
//	@Param			workoutId		path		string	true	"Workout ID"
//	@Success		200				{object}	Workout
//	@Failure		401				{object}	ErrorResponse	"Unauthorized"
//	@Failure		404				{object}	ErrorResponse	"Not Found"
//	@Failure		500				{object}	ErrorResponse	"Server error"
//	@Router			/workouts/{workoutId} [get]
//	@Security		BearerAuth
func GetWorkout(c *gin.Context, userId string) (any, error) {
	workoutId := c.Param("workoutId")

	workout, err := dbGetWorkout(c.Request.Context(), userId, workoutId)

	if err != nil {
		return nil, models.NewServerError(err)
	}

	return models.NewWorkoutOut(workout, config.App.MediaDistributionAlias), nil
}

// MakeWorkout godoc
//
//	@Summary		Creates a workout
//	@Description	Validates, saves and returns a workout
//	@Tags			workouts
//	@Accept			json
//	@Produce		json
//	@ID				makeWorkout
//	@Param			X-App-Version	header		string		false	"Client app version"
//	@Param			input			body		WorkoutIn	true	"Workout request"
//	@Success		200				{object}	Workout
//	@Failure		401				{object}	ErrorResponse	"Unauthorized"
//	@Failure		500				{object}	ErrorResponse	"Server error"
//	@Router			/workouts [post]
//	@Security		BearerAuth
func MakeWorkout(c *gin.Context, userID string) (any, error) {
	var workoutIn models.WorkoutIn
	if err := c.BindJSON(&workoutIn); err != nil {
		return nil, models.NewValidationError(err)
	}

	workout := models.NewWorkout(&workoutIn, userID)

	saved, err := dbx.SaveWorkout(c.Request.Context(), workout)
	if err != nil {
		return nil, err
	}

	return models.NewWorkoutOut(saved, config.App.MediaDistributionAlias), nil
}

// DeleteWorkout godoc
//
//	@Summary		Deletes a workout
//	@Description	Deletes a workout by ID
//	@Tags			workouts
//	@Accept			json
//	@Produce		json
//	@ID				deleteWorkout
//	@Param			X-App-Version	header	string	false	"Client app version"
//	@Param			workoutId		path	string	true	"Workout ID"
//	@Success		204				"No Content"
//	@Failure		401				{object}	ErrorResponse	"Unauthorized"
//	@Failure		404				{object}	ErrorResponse	"Not Found"
//	@Failure		500				{object}	ErrorResponse	"Server error"
//	@Router			/workouts/{workoutId} [delete]
//	@Security		BearerAuth
func DeleteWorkout(c *gin.Context, userId string) (any, error) {
	workoutId := c.Param("workoutId")

	err := dbDeleteWorkout(c.Request.Context(), userId, workoutId)

	var notFound *models.NotFoundError
	if ok := errors.As(err, &notFound); ok {
		return nil, err
	}

	if err != nil {
		return nil, models.NewServerError(err)
	}

	return models.NoContent, nil
}

// MakeWorkoutPresignedUrl godoc
//
//	@Summary		Generates presigned URL for workout file upload
//	@Description	Generates presigned URL and form fields for uploading workout files to S3
//	@Tags			workouts
//	@Accept			json
//	@Produce		json
//	@ID				makeWorkoutPresignedUrl
//	@Param			X-App-Version	header		string		false	"Client app version"
//	@Param			workoutId		path		string		true	"Workout ID"
//	@Param			input			body		HasMimeType true	"Upload request"
//	@Success		200				{object}	PresignedUrlResponse
//	@Failure		401				{object}	ErrorResponse	"Unauthorized"
//	@Failure		500				{object}	ErrorResponse	"Server error"
//	@Router			/workouts/{workoutId}/image [put]
//	@Security		BearerAuth
func MakeWorkoutPresignedUrl(c *gin.Context, userId string) (any, error) {
	workoutId := c.Param("workoutId")

	var request models.HasMimeType
	if err := c.BindJSON(&request); err != nil {
		return nil, models.NewValidationError(err)
	}

	tag := config.App.UploadDestinationTag()

	maps.Copy(tag, map[string]string{"userId": userId, "workoutId": workoutId})

	var mimeType string
	if request.MimeType == nil || *request.MimeType == "" {
		mimeType = models.DefaultMimeType
	} else {
		mimeType = *request.MimeType
	}

	var extension, err = models.Extension(mimeType)

	if err != nil {
		return nil, models.NewServerError(err)
	}

	key, err := workoutImageKey(userId, workoutId, extension)

	if err != nil {
		return nil, models.NewServerError(err)
	}

	response, err := awsx.GeneratePresignedPostURL(
		c.Request.Context(),
		config.App.UploadBucket,
		key,
		mimeType,
		&tag,
	)

	if err != nil {
		return nil, models.NewServerError(err)
	}

	destinationUrl := fmt.Sprintf("%s/%s", config.App.MediaDistributionAlias, key)
	return models.PresignedUrlResponse{
		URL:            response.URL,
		Fields:         response.Values,
		DestinationUrl: &destinationUrl,
	}, nil
}

func workoutImageKey(userId, workoutId, extension string) (string, error) {
	h := sha256.Sum256([]byte(userId + ":" + workoutId))
	hash := hex.EncodeToString(h[:])[:16] // 16 hex chars = 64 bits, plenty unique
	id, err := uuid.NewV7()

	if err != nil {
		return "", err
	}

	return fmt.Sprintf("workouts/%s/%s%s", hash, id, extension), err
}

// DeleteWorkoutImage godoc
//
//	@Summary		Deletes a workout image
//	@Description	Deletes the image associated with a workout from S3 and removes the image reference from DynamoDB
//	@Tags			workouts
//	@Accept			json
//	@Produce		json
//	@ID				deleteWorkoutImage
//	@Param			X-App-Version	header	string	false	"Client app version"
//	@Param			workoutId		path	string	true	"Workout ID"
//	@Param			imageId			query	string	true	"Image ID"
//	@Success		204				"No Content"
//	@Failure		401				{object}	ErrorResponse	"Unauthorized"
//	@Failure		404				{object}	ErrorResponse	"Not Found"
//	@Failure		500				{object}	ErrorResponse	"Server error"
//	@Router			/workouts/{workoutId}/images [delete]
//	@Security		BearerAuth
func DeleteWorkoutImage(c *gin.Context, userId string) (any, error) {
	workoutId := c.Param("workoutId")

	// Expect the client to send the S3 key to delete, e.g.:
	// DELETE /workouts/{workoutId}/image?key=workouts/<hash>/<uuidv7>.png
	key := strings.TrimSpace(c.Query("key"))
	key = strings.TrimPrefix(key, "/")
	if key == "" {
		return nil, models.NewValidationError(errors.New("missing query param: key"))
	}

	workout, err := dbGetWorkout(c.Request.Context(), userId, workoutId)
	if err != nil {
		return nil, err
	}

	if workout == nil {
		return nil, models.NewForbiddenError("Forbidden", errors.New("workout not found"))
	}

	found := false
	if workout.ImageKeys != nil {
		for _, k := range *workout.ImageKeys {
			if k == key {
				found = true
				break
			}
		}
	}

	if !found {
		return models.NoContent, nil
	}

	_, err = awsx.DeleteObject(c.Request.Context(), config.App.MediaBucket, key)
	if err != nil {
		return nil, models.NewServerError(err)
	}

	if err = removeWorkoutImage(c.Request.Context(), userId, workoutId, key); err != nil {
		return nil, err
	}

	return models.NoContent, nil
}

// GetWorkoutGallery godoc
//
//	@Summary		Returns workout progress gallery
//	@Description	Returns paginated list of workout progress images
//	@Tags			workouts
//	@Accept			json
//	@Produce		json
//	@ID				getWorkoutGallery
//	@Param			X-App-Version	header		string	false	"Client app version"
//	@Param			pageSize		query		integer	false	"Page size for pagination"
//	@Param			cursor			query		string	false	"Cursor for pagination"
//	@Success		200				{object}	ProgressGalleryResponse
//	@Failure		401				{object}	ErrorResponse	"Unauthorized"
//	@Failure		500				{object}	ErrorResponse	"Server error"
//	@Router			/workouts/images [get]
//	@Security		BearerAuth
func GetWorkoutGallery(c *gin.Context, userId string) (any, error) {
	pageSize := 20
	if size := c.Query("pageSize"); size != "" {
		if parsed, err := strconv.Atoi(size); err == nil && parsed > 0 {
			pageSize = parsed
		}
	}

	cursor := c.Query("cursor")

	items, next, err := dbGetWorkoutGallery(c.Request.Context(), userId, pageSize, cursor)
	if err != nil {
		return nil, models.NewServerError(err)
	}

	return models.ProgressGalleryResponse{
		Images: items,
		Cursor: next,
	}, nil
}
