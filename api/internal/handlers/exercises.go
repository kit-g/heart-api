package handlers

import (
	"heart/internal/dbx"
	"heart/internal/models"

	"github.com/gin-gonic/gin"
)

// test seams for dbx dependencies
var (
	dbGetExercises = dbx.GetExercises
	dbMakeExercise = dbx.MakeExercise
)

// GetExercises godoc
//
//	@Summary		List all exercises
//	@Description	Returns all exercises in a single page
//	@Tags			workouts
//	@Accept			json
//	@Produce		json
//	@ID				getExercises
//	@Param			X-App-Version	header		string	false	"Client app version (e.g., 2.8.0)"
//	@Success		200				{object}	ExercisesResponse
//	@Failure		401				{object}	ErrorResponse	"Unauthorized"
//	@Failure		500				{object}	ErrorResponse	"Server error"
//	@Router			/exercises [get]
//	@Security		BearerAuth
func GetExercises(c *gin.Context, _ string) (any, error) {
	exercises, err := dbGetExercises(c.Request.Context())

	if err != nil {
		return nil, models.NewServerError(err)
	}

	out := models.ExercisesResponse{
		Exercises: make([]models.ExerciseOut, len(exercises)),
	}
	for i, e := range exercises {
		out.Exercises[i] = models.NewExerciseOut(&e)
	}

	return out, nil
}

// MakeExercise godoc
//
//	@Summary		Create new exercise
//	@Description	Creates a new user exercise with the provided details
//	@Tags			workouts
//	@Accept			json
//	@Produce		json
//	@ID				makeExercise
//	@Param			X-App-Version	header		string			false	"Client app version (e.g., 2.8.0)"
//	@Param			exercise		body		UserExerciseIn	true	"Exercise details"
//	@Success		200				{object}	Exercise
//	@Failure		400				{object}	ErrorResponse	"Validation error"
//	@Failure		401				{object}	ErrorResponse	"Unauthorized"
//	@Failure		500				{object}	ErrorResponse	"Server error"
//	@Router			/exercises [post]
//	@Security		BearerAuth
func MakeExercise(c *gin.Context, userId string) (any, error) {
	var exercise models.UserExerciseIn
	if err := c.BindJSON(&exercise); err != nil {
		return nil, models.NewValidationError(err)
	}

	made, err := dbMakeExercise(c, exercise, userId)
	if err != nil {
		return nil, err
	}

	return models.ExerciseOut{
		Name:         made.Name,
		Category:     made.Category,
		Target:       made.Target,
		Instructions: made.Instructions,
	}, nil
}
