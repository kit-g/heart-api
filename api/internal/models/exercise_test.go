package models

import (
	"net/url"
	"strings"
	"testing"

	"github.com/aws/smithy-go/ptr"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestExercise_String(t *testing.T) {
	tests := []struct {
		name     string
		exercise Exercise
		expected string
	}{
		{
			name: "Exercise with name",
			exercise: Exercise{
				Name: "Push Up",
			},
			expected: "Push Up",
		},
		{
			name: "Exercise with empty name",
			exercise: Exercise{
				Name: "",
			},
			expected: "",
		},
		{
			name: "Exercise with long name",
			exercise: Exercise{
				Name: "This is a very long exercise name that might be used in some cases",
			},
			expected: "This is a very long exercise name that might be used in some cases",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := tt.exercise.String()
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestNewExerciseOut(t *testing.T) {
	t.Run("Exercise with all fields", func(t *testing.T) {
		exercise := &Exercise{
			Name:     "Push Up",
			Category: "Body weight",
			Target:   "Chest",
			Asset: &ImageDescription{
				Link:   strP("https://example.com/pushup.jpg"),
				Width:  intP(800),
				Height: intP(600),
			},
			//Asset:           ,
			Thumbnail: &ImageDescription{
				Link:   strP("https://example.com/pushup-thumb.jpg"),
				Width:  intP(200),
				Height: intP(150),
			},
			Instructions: strP("Keep your body straight and lower yourself until your chest almost touches the ground."),
		}

		result := NewExerciseOut(exercise)

		assert.Equal(t, "Push Up", result.Name)
		assert.Equal(t, "Body weight", result.Category)
		assert.Equal(t, "Chest", result.Target)

		require.NotNil(t, result.Asset)
		assert.Equal(t, "https://example.com/pushup.jpg", *result.Asset.Link)
		assert.Equal(t, 800, *result.Asset.Width)
		assert.Equal(t, 600, *result.Asset.Height)

		require.NotNil(t, result.Thumbnail)
		assert.Equal(t, "https://example.com/pushup-thumb.jpg", *result.Thumbnail.Link)
		assert.Equal(t, 200, *result.Thumbnail.Width)
		assert.Equal(t, 150, *result.Thumbnail.Height)

		require.NotNil(t, result.Instructions)
		assert.Equal(t, "Keep your body straight and lower yourself until your chest almost touches the ground.", *result.Instructions)
	})

	t.Run("Exercise with minimal fields", func(t *testing.T) {
		exercise := &Exercise{
			Name:     "Squat",
			Category: "Body weight",
			Target:   "Legs",
		}

		result := NewExerciseOut(exercise)

		assert.Equal(t, "Squat", result.Name)
		assert.Equal(t, "Body weight", result.Category)
		assert.Equal(t, "Legs", result.Target)
		assert.Nil(t, result.Asset)
		assert.Nil(t, result.Thumbnail)
		require.Nil(t, result.Instructions)
	})

	t.Run("Exercise with only asset", func(t *testing.T) {
		exercise := &Exercise{
			Name:     "Plank",
			Category: "Core",
			Target:   "Abs",
			Asset: &ImageDescription{
				Link:   strP("https://example.com/plank.jpg"),
				Width:  intP(400),
				Height: intP(300),
			},
		}

		result := NewExerciseOut(exercise)

		assert.Equal(t, "Plank", result.Name)
		require.NotNil(t, result.Asset)
		assert.Equal(t, "https://example.com/plank.jpg", *result.Asset.Link)
		assert.Equal(t, 400, *result.Asset.Width)
		assert.Equal(t, 300, *result.Asset.Height)
		assert.Nil(t, result.Thumbnail)
	})

	t.Run("Exercise with only thumbnail", func(t *testing.T) {
		exercise := &Exercise{
			Name:     "Burpee",
			Category: "Cardio",
			Target:   "Full body",
			Thumbnail: &ImageDescription{
				Link:   strP("https://example.com/burpee-thumb.jpg"),
				Width:  intP(100),
				Height: intP(75),
			},
		}

		result := NewExerciseOut(exercise)

		assert.Equal(t, "Burpee", result.Name)
		assert.Nil(t, result.Asset)
		require.NotNil(t, result.Thumbnail)
		assert.Equal(t, "https://example.com/burpee-thumb.jpg", *result.Thumbnail.Link)
		assert.Equal(t, 100, *result.Thumbnail.Width)
		assert.Equal(t, 75, *result.Thumbnail.Height)
	})
}

func TestExerciseStructFields(t *testing.T) {
	t.Run("Exercise with all fields", func(t *testing.T) {
		exercise := Exercise{
			Name:     "Push Up",
			Category: "Body weight",
			Target:   "Chest",
			Asset: &ImageDescription{
				Link:   strP("https://example.com/asset.jpg"),
				Width:  intP(800),
				Height: intP(600),
			},
			Thumbnail: &ImageDescription{
				Link:   strP("https://example.com/thumb.jpg"),
				Width:  intP(200),
				Height: intP(150),
			},
			Instructions: strP("Push up instructions"),
			UserID:       "user123",
		}

		assert.Equal(t, "Push Up", exercise.Name)
		assert.Equal(t, "Body weight", exercise.Category)
		assert.Equal(t, "Chest", exercise.Target)
		assert.Equal(t, "https://example.com/asset.jpg", *exercise.Asset.Link)
		assert.Equal(t, 800, *exercise.Asset.Width)
		assert.Equal(t, 600, *exercise.Asset.Height)
		assert.Equal(t, "https://example.com/thumb.jpg", *exercise.Thumbnail.Link)
		assert.Equal(t, 200, *exercise.Thumbnail.Width)
		assert.Equal(t, 150, *exercise.Thumbnail.Height)
		assert.Equal(t, "Push up instructions", *exercise.Instructions)
		assert.Equal(t, "user123", exercise.UserID)
	})
}

func TestNewUserExercise_BuildsKeys(t *testing.T) {
	in := &UserExerciseIn{Name: "Push Up", Category: "Body", Target: "Chest"}
	out := NewUserExercise(in, "user-1")
	assert.Equal(t, UserKey+"user-1", out.PK)
	assert.Equal(t, ExerciseKey+strings.ToLower(url.PathEscape("Push Up")), out.SK)
	assert.Equal(t, in.Name, out.Name)
	assert.Equal(t, in.Category, out.Category)
	assert.Equal(t, in.Target, out.Target)
}

func strP(v string) *string {
	return ptr.String(v)
}

func intP(v int) *int {
	return ptr.Int(v)
}
