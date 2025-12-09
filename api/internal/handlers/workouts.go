package handlers

import (
	"errors"
	"fmt"
	"heart/internal/awsx"
	"heart/internal/config"
	"heart/internal/dbx"
	"heart/internal/models"
	"strconv"

	"github.com/gin-gonic/gin"
)

// test seams for dbx dependencies
var (
	dbGetWorkouts   = dbx.GetWorkouts
	dbGetWorkout    = dbx.GetWorkout
	dbDeleteWorkout = dbx.DeleteWorkout
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
		Workouts: models.NewWorkoutsArray(workouts),
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

	return models.NewWorkoutOut(workout), nil
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

	return models.NewWorkoutOut(saved), nil
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
//	@Router			/workouts/{workoutId} [put]
//	@Security		BearerAuth
func MakeWorkoutPresignedUrl(c *gin.Context, userId string) (any, error) {
	workoutId := c.Param("workoutId")

	var request models.HasMimeType
	if err := c.BindJSON(&request); err != nil {
		return nil, models.NewValidationError(err)
	}

	tag := config.App.UploadDestinationTag()

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

	response, err := awsx.GeneratePresignedPostURL(
		c.Request.Context(),
		config.App.UploadBucket,
		fmt.Sprintf("workouts/user-%s/workout-%s%s", userId, workoutId, extension),
		mimeType,
		&tag,
	)

	if err != nil {
		return nil, models.NewServerError(err)
	}

	return models.PresignedUrlResponse{
		URL:    response.URL,
		Fields: response.Values,
	}, nil
}
