package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"heart/internal/models"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
)

func newCtx() *gin.Context {
	gin.SetMode(gin.TestMode)
	rec := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(rec)
	// Attach a dummy request so c.Request.Context() is valid in handlers
	c.Request = httptest.NewRequest("GET", "/exercises", nil)
	return c
}

func TestGetExercises_Success(t *testing.T) {
	orig := dbGetExercises
	dbGetExercises = func(ctx context.Context) ([]models.Exercise, error) {
		return []models.Exercise{{Name: "Push Up", Category: "Body", Target: "Chest"}}, nil
	}
	t.Cleanup(func() { dbGetExercises = orig })

	c := newCtx()
	res, err := GetExercises(c, "user")
	assert.NoError(t, err)
	out, ok := res.(models.ExercisesResponse)
	assert.True(t, ok)
	assert.Len(t, out.Exercises, 1)
	assert.Equal(t, "Push Up", out.Exercises[0].Name)
}

func TestGetExercises_ServerError(t *testing.T) {
	orig := dbGetExercises
	dbGetExercises = func(ctx context.Context) ([]models.Exercise, error) { return nil, errors.New("boom") }
	t.Cleanup(func() { dbGetExercises = orig })

	c := newCtx()
	res, err := GetExercises(c, "user")
	assert.Nil(t, res)
	assert.Error(t, err)
	_, isHTTP := err.(models.HTTPError)
	assert.True(t, isHTTP)
}

func TestMakeExercise_Success(t *testing.T) {
	orig := dbMakeExercise
	dbMakeExercise = func(ctx context.Context, in models.UserExerciseIn, userId string) (*models.UserExerciseIn, error) {
		return &in, nil
	}
	t.Cleanup(func() { dbMakeExercise = orig })

	gin.SetMode(gin.TestMode)
	rec := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(rec)
	body := models.UserExerciseIn{Name: "Push Up", Category: "Body", Target: "Chest"}
	b, _ := json.Marshal(body)
	c.Request = httptest.NewRequest("POST", "/exercises", bytes.NewReader(b))
	c.Request.Header.Set("Content-Type", "application/json")

	res, err := MakeExercise(c, "user-1")
	assert.NoError(t, err)
	out, ok := res.(models.ExerciseOut)
	assert.True(t, ok)
	assert.Equal(t, body.Name, out.Name)
	assert.Equal(t, body.Category, out.Category)
	assert.Equal(t, body.Target, out.Target)
}

func TestMakeExercise_BadJSON(t *testing.T) {
	orig := dbMakeExercise
	dbMakeExercise = func(ctx context.Context, in models.UserExerciseIn, userId string) (*models.UserExerciseIn, error) {
		return &in, nil
	}
	t.Cleanup(func() { dbMakeExercise = orig })

	gin.SetMode(gin.TestMode)
	rec := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(rec)
	c.Request = httptest.NewRequest("POST", "/exercises", bytes.NewBufferString("{bad json"))
	c.Request.Header.Set("Content-Type", "application/json")

	res, err := MakeExercise(c, "user-1")
	assert.Nil(t, res)
	assert.Error(t, err)
	_, isHTTP := err.(models.HTTPError)
	assert.True(t, isHTTP)
}

func TestMakeExercise_PropagatesError(t *testing.T) {
	orig := dbMakeExercise
	dbMakeExercise = func(ctx context.Context, in models.UserExerciseIn, userId string) (*models.UserExerciseIn, error) {
		return nil, errors.New("db fail")
	}
	t.Cleanup(func() { dbMakeExercise = orig })

	gin.SetMode(gin.TestMode)
	rec := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(rec)
	body := models.UserExerciseIn{Name: "Push Up", Category: "Body", Target: "Chest"}
	b, _ := json.Marshal(body)
	c.Request = httptest.NewRequest("POST", "/exercises", bytes.NewReader(b))
	c.Request.Header.Set("Content-Type", "application/json")

	res, err := MakeExercise(c, "user-1")
	assert.Nil(t, res)
	assert.Error(t, err)
}
