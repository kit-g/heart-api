package handlers

import (
	"context"
	"errors"
	"heart/internal/models"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
)

func TestGetWorkouts_DefaultsAndHappyPath(t *testing.T) {
	orig := dbGetWorkouts
	var gotUser string
	var gotPage int
	var gotCursor string
	dbGetWorkouts = func(ctx context.Context, userId string, pageSize int, cursor string) ([]models.Workout, string, error) {
		gotUser, gotPage, gotCursor = userId, pageSize, cursor
		ws := []models.Workout{{PK: models.UserKey + userId, SK: models.WorkoutKey + "w1", Name: "W"}}
		return ws, "next", nil
	}
	t.Cleanup(func() { dbGetWorkouts = orig })

	c := newCtx()
	// no pageSize, no cursor
	res, err := GetWorkouts(c, "u1")
	assert.NoError(t, err)
	assert.Equal(t, "u1", gotUser)
	assert.Equal(t, 10, gotPage)
	assert.Equal(t, "", gotCursor)
	out, ok := res.(models.WorkoutResponse)
	assert.True(t, ok)
	assert.Equal(t, "next", out.Cursor)
	assert.Len(t, out.Workouts, 1)
}

func TestGetWorkouts_CustomPageAndCursor(t *testing.T) {
	orig := dbGetWorkouts
	var gotPage int
	var gotCursor string
	dbGetWorkouts = func(ctx context.Context, userId string, pageSize int, cursor string) ([]models.Workout, string, error) {
		gotPage, gotCursor = pageSize, cursor
		return nil, "", nil
	}
	t.Cleanup(func() { dbGetWorkouts = orig })

	rec := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(rec)
	c.Request = httptest.NewRequest("GET", "/workouts?pageSize=25&cursor=abc", nil)

	res, err := GetWorkouts(c, "u1")
	assert.NoError(t, err)
	assert.NotNil(t, res)
	assert.Equal(t, 25, gotPage)
	assert.Equal(t, "abc", gotCursor)
}

func TestGetWorkout_ErrorMapping(t *testing.T) {
	orig := dbGetWorkout
	dbGetWorkout = func(ctx context.Context, userId, id string) (*models.Workout, error) { return nil, errors.New("boom") }
	t.Cleanup(func() { dbGetWorkout = orig })

	c := newCtx()
	c.Params = gin.Params{{Key: "workoutId", Value: "w1"}}
	res, err := GetWorkout(c, "u1")
	assert.Nil(t, res)
	_, isHTTP := err.(models.HTTPError)
	assert.True(t, isHTTP)
}

func TestMakeWorkout_ValidationError(t *testing.T) {
	c := newGinContextWithBody("POST", "/workouts", "not json")
	res, err := MakeWorkout(c, "u1")
	assert.Nil(t, res)
	_, isHTTP := err.(models.HTTPError)
	assert.True(t, isHTTP)
}

func TestDeleteWorkout_NotFoundPassthrough(t *testing.T) {
	orig := dbDeleteWorkout
	dbDeleteWorkout = func(ctx context.Context, userId, id string) error {
		return models.NewNotFoundError("not found", errors.New("nf"))
	}
	t.Cleanup(func() { dbDeleteWorkout = orig })

	c := newCtx()
	c.Params = gin.Params{{Key: "workoutId", Value: "w1"}}
	res, err := DeleteWorkout(c, "u1")
	assert.Nil(t, res)
	var nf *models.NotFoundError
	assert.ErrorAs(t, err, &nf)
}
