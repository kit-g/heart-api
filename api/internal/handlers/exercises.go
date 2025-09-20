package handlers

import (
	"heart/internal/dbx"
	"heart/internal/models"

	"github.com/gin-gonic/gin"
)

// test seams for dbx dependencies
var (
	dbGetExercises    = dbx.GetExercises
	dbGetOwnExercises = dbx.GetOwnExercises
	dbMakeExercise    = dbx.MakeExercise
	dbEditExercise    = dbx.EditExercise
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
//	@Param			owned			query		boolean	false	"Filter exercises created by the authenticated user"
//	@Success		200				{object}	ExercisesResponse
//	@Failure		401				{object}	ErrorResponse	"Unauthorized"
//	@Failure		500				{object}	ErrorResponse	"Server error"
//	@Router			/exercises [get]
//	@Security		BearerAuth
func GetExercises(c *gin.Context, userId string) (any, error) {
	owned := c.Query("owned") == "true"
	var exercises []models.Exercise
	var err error
	if owned {
		exercises, err = dbGetOwnExercises(c.Request.Context(), userId)
	} else {
		exercises, err = dbGetExercises(c.Request.Context())
	}

	if err != nil {
		return nil, models.NewServerError(err)
	}

	out := models.ExercisesResponse{
		Exercises: make([]models.ExerciseOut, len(exercises)),
	}
	for i, e := range exercises {
		ex := models.NewExerciseOut(&e)
		if owned {
			ex.Own = boolPtr(true)
		} else {
			ex.Own = boolPtr(false)
		}
		out.Exercises[i] = ex
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
//	@Param			exercise		body		UserExercise	true	"Exercise details"
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

// EditExercise godoc
//
//	@Summary		Edit an exercise
//	@Description	Edits target, category and instructions for the exercise created by the authenticated user
//	@Tags			workouts
//	@Accept			json
//	@Produce		json
//	@ID				editExercise
//	@Param			X-App-Version	header		string			false	"Client app version (e.g., 2.8.0)"
//	@Param			exerciseName	path		string			true	"Name of the exercise to edit"
//	@Param			input			body		EditExerciseIn	true	"Exercise fields to edit"
//	@Success		200				{object}	Exercise
//	@Failure		400				{object}	ErrorResponse	"Validation error"
//	@Failure		401				{object}	ErrorResponse	"Unauthorized"
//	@Failure		500				{object}	ErrorResponse	"Server error"
//	@Router			/exercises/{exerciseName} [put]
//	@Security		BearerAuth
func EditExercise(c *gin.Context, userId string) (any, error) {
	exerciseName := c.Param("exerciseName")
	var in models.EditExerciseIn
	if err := c.BindJSON(&in); err != nil {
		return nil, models.NewValidationError(err)
	}

	updated, err := dbEditExercise(c.Request.Context(), userId, exerciseName, in)
	if err != nil {
		return nil, err
	}
	out := models.NewExerciseOut(updated)
	out.Own = boolPtr(true)
	return out, nil
}

func boolPtr(b bool) *bool { return &b }
