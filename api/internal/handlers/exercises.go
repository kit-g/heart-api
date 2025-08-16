package handlers

import (
	"heart/internal/dbx"
	"heart/internal/models"

	"github.com/gin-gonic/gin"
)

// test seams for dbx dependencies
var (
	dbGetExercises = dbx.GetExercises
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
