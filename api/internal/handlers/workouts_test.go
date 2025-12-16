package handlers

import (
	"context"
	"errors"
	"heart/internal/config"
	"heart/internal/models"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
)

func TestMain(m *testing.M) {
	// Minimal config needed by handlers that build media URLs.
	config.App = &config.AppConfig{
		AwsConfig: config.AwsConfig{
			CloudFrontConfig: config.CloudFrontConfig{
				MediaDistributionAlias: "https://media.example.test",
			},
		},
	}

	os.Exit(m.Run())
}

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
	var HTTPError models.HTTPError
	isHTTP := errors.As(err, &HTTPError)
	assert.True(t, isHTTP)
}

func TestMakeWorkout_ValidationError(t *testing.T) {
	c := newGinContextWithBody("POST", "/workouts", "not json")
	res, err := MakeWorkout(c, "u1")
	assert.Nil(t, res)
	var HTTPError models.HTTPError
	isHTTP := errors.As(err, &HTTPError)
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

func TestGetWorkoutGallery_DefaultsAndHappyPath(t *testing.T) {
	orig := dbGetWorkoutGallery
	var gotUser string
	var gotPage int
	var gotCursor string

	dbGetWorkoutGallery = func(ctx context.Context, userId string, pageSize int, cursor string) ([]models.ProgressImage, *string, error) {
		gotUser, gotPage, gotCursor = userId, pageSize, cursor
		next := "2025-07-01T00:00:00Z#2025-12-01T00:00:00Z~aaaa"
		items := []models.ProgressImage{
			{
				WorkoutID: "2025-07-25T18:20:01.253622Z",
				PhotoID:   "2025-12-11T20:41:16.797Z~deadbeef",
			},
		}
		return items, &next, nil
	}
	t.Cleanup(func() { dbGetWorkoutGallery = orig })

	c := newCtx() // no pageSize, no cursor
	res, err := GetWorkoutGallery(c, "u1")
	assert.NoError(t, err)

	assert.Equal(t, "u1", gotUser)
	assert.Equal(t, 20, gotPage)
	assert.Equal(t, "", gotCursor)

	out, ok := res.(models.ProgressGalleryResponse)
	assert.True(t, ok)
	assert.Len(t, out.Images, 1)
	assert.NotNil(t, out.Cursor)
	assert.Equal(t, "2025-07-01T00:00:00Z#2025-12-01T00:00:00Z~aaaa", *out.Cursor)
}

func TestGetWorkoutGallery_CustomPageAndCursor(t *testing.T) {
	orig := dbGetWorkoutGallery
	var gotPage int
	var gotCursor string

	dbGetWorkoutGallery = func(ctx context.Context, userId string, pageSize int, cursor string) ([]models.ProgressImage, *string, error) {
		gotPage, gotCursor = pageSize, cursor
		return nil, nil, nil
	}
	t.Cleanup(func() { dbGetWorkoutGallery = orig })

	rec := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(rec)
	c.Request = httptest.NewRequest("GET", "/workouts/images?pageSize=25&cursor=abc", nil)

	res, err := GetWorkoutGallery(c, "u1")
	assert.NoError(t, err)
	assert.NotNil(t, res)
	assert.Equal(t, 25, gotPage)
	assert.Equal(t, "abc", gotCursor)
}

func TestGetWorkoutGallery_DBErrorMapping(t *testing.T) {
	orig := dbGetWorkoutGallery
	dbGetWorkoutGallery = func(ctx context.Context, userId string, pageSize int, cursor string) ([]models.ProgressImage, *string, error) {
		return nil, nil, errors.New("boom")
	}
	t.Cleanup(func() { dbGetWorkoutGallery = orig })

	c := newCtx()
	res, err := GetWorkoutGallery(c, "u1")

	assert.Nil(t, res)
	var HTTPError models.HTTPError
	isHTTP := errors.As(err, &HTTPError)
	assert.True(t, isHTTP)
}
