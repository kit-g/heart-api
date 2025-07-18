package models

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestTemplate_StructFields(t *testing.T) {
	t.Run("Template with all fields", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		exercises := []TemplateExercise{
			{
				ID:            "exercise1",
				ExerciseID:    "push_up",
				ExerciseOrder: 1,
				Sets: []Set{
					{
						ID:        "set1",
						Completed: true,
						Weight:    80.0,
						Reps:      10,
					},
				},
			},
		}

		template := Template{
			PK:            UserKey + "user123",
			SK:            TemplateKey + id,
			Name:          "Upper Body Workout",
			OrderInParent: 1,
			Exercises:     exercises,
		}

		assert.Equal(t, id, template.ID())
		assert.Equal(t, "Upper Body Workout", template.Name)
		assert.Equal(t, "user123", template.UserID())
		assert.Equal(t, 1, template.OrderInParent)
		assert.Len(t, template.Exercises, 1)
		assert.Equal(t, "push_up", template.Exercises[0].ExerciseID)
		assert.Equal(t, "exercise1", template.Exercises[0].ID)
	})

	t.Run("Template with minimal fields", func(t *testing.T) {
		template := Template{
			Name: "Minimal Template",
			PK:   UserKey + "user456",
		}

		assert.Equal(t, "Minimal Template", template.Name)
		assert.Equal(t, "user456", template.UserID())
		assert.Equal(t, 0, template.OrderInParent)
		assert.Len(t, template.Exercises, 0)
	})

	t.Run("Template with empty exercises", func(t *testing.T) {
		template := Template{
			Name:      "Empty Template",
			PK:        UserKey + "user789",
			Exercises: []TemplateExercise{},
		}

		assert.Equal(t, "Empty Template", template.Name)
		assert.Equal(t, "user789", template.UserID())
		assert.NotNil(t, template.Exercises)
		assert.Len(t, template.Exercises, 0)
	})
}

func TestTemplate_IDMethods(t *testing.T) {
	t.Run("Template UserID extraction", func(t *testing.T) {
		template := Template{
			PK: UserKey + "testuser123",
		}

		assert.Equal(t, "testuser123", template.UserID())
	})

	t.Run("Template ID extraction", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		template := Template{
			SK: TemplateKey + id,
		}

		assert.Equal(t, id, template.ID())
	})

	t.Run("Template with empty PK", func(t *testing.T) {
		template := Template{
			PK: UserKey,
		}

		assert.Equal(t, "", template.UserID())
	})

	t.Run("Template with empty SK", func(t *testing.T) {
		template := Template{
			SK: TemplateKey,
		}

		assert.Equal(t, "", template.ID())
	})
}

func TestTemplateExercise_StructFields(t *testing.T) {
	t.Run("TemplateExercise with all fields", func(t *testing.T) {
		sets := []Set{
			{
				ID:        "set1",
				Completed: true,
				Weight:    100.0,
				Reps:      12,
				Duration:  30.0,
				Distance:  0.0,
			},
			{
				ID:        "set2",
				Completed: false,
				Weight:    105.0,
				Reps:      10,
				Duration:  35.0,
				Distance:  0.0,
			},
		}

		exercise := TemplateExercise{
			ID:            "exercise1",
			ExerciseID:    "bench_press",
			ExerciseOrder: 2,
			Sets:          sets,
		}

		assert.Equal(t, "exercise1", exercise.ID)
		assert.Equal(t, "bench_press", exercise.ExerciseID)
		assert.Equal(t, 2, exercise.ExerciseOrder)
		assert.Len(t, exercise.Sets, 2)

		assert.Equal(t, "set1", exercise.Sets[0].ID)
		assert.True(t, exercise.Sets[0].Completed)
		assert.Equal(t, 100.0, exercise.Sets[0].Weight)
		assert.Equal(t, 12, exercise.Sets[0].Reps)

		assert.Equal(t, "set2", exercise.Sets[1].ID)
		assert.False(t, exercise.Sets[1].Completed)
		assert.Equal(t, 105.0, exercise.Sets[1].Weight)
		assert.Equal(t, 10, exercise.Sets[1].Reps)
	})

	t.Run("TemplateExercise with no sets", func(t *testing.T) {
		exercise := TemplateExercise{
			ID:            "exercise2",
			ExerciseID:    "plank",
			ExerciseOrder: 1,
			Sets:          []Set{},
		}

		assert.Equal(t, "exercise2", exercise.ID)
		assert.Equal(t, "plank", exercise.ExerciseID)
		assert.Equal(t, 1, exercise.ExerciseOrder)
		assert.Len(t, exercise.Sets, 0)
	})

	t.Run("TemplateExercise with zero order", func(t *testing.T) {
		exercise := TemplateExercise{
			ID:            "exercise3",
			ExerciseID:    "squat",
			ExerciseOrder: 0,
			Sets: []Set{
				{
					ID:        "set3",
					Completed: true,
					Weight:    50.0,
					Reps:      15,
				},
			},
		}

		assert.Equal(t, "exercise3", exercise.ID)
		assert.Equal(t, "squat", exercise.ExerciseID)
		assert.Equal(t, 0, exercise.ExerciseOrder)
		assert.Len(t, exercise.Sets, 1)
		assert.Equal(t, "set3", exercise.Sets[0].ID)
	})

	t.Run("TemplateExercise with cardio sets", func(t *testing.T) {
		exercise := TemplateExercise{
			ID:            "exercise4",
			ExerciseID:    "running",
			ExerciseOrder: 3,
			Sets: []Set{
				{
					ID:        "set4",
					Completed: true,
					Weight:    0.0,
					Reps:      0,
					Duration:  1800.0, // 30 minutes
					Distance:  5.0,    // 5 km
				},
			},
		}

		assert.Equal(t, "exercise4", exercise.ID)
		assert.Equal(t, "running", exercise.ExerciseID)
		assert.Equal(t, 3, exercise.ExerciseOrder)
		assert.Len(t, exercise.Sets, 1)
		assert.Equal(t, "set4", exercise.Sets[0].ID)
		assert.True(t, exercise.Sets[0].Completed)
		assert.Equal(t, 0.0, exercise.Sets[0].Weight)
		assert.Equal(t, 0, exercise.Sets[0].Reps)
		assert.Equal(t, 1800.0, exercise.Sets[0].Duration)
		assert.Equal(t, 5.0, exercise.Sets[0].Distance)
	})

	t.Run("TemplateExercise with empty ID", func(t *testing.T) {
		exercise := TemplateExercise{
			ID:            "",
			ExerciseID:    "test_exercise",
			ExerciseOrder: 1,
			Sets:          []Set{},
		}

		assert.Equal(t, "", exercise.ID)
		assert.Equal(t, "test_exercise", exercise.ExerciseID)
		assert.Equal(t, 1, exercise.ExerciseOrder)
		assert.Len(t, exercise.Sets, 0)
	})
}

func TestTemplateIn_StructFields(t *testing.T) {
	t.Run("TemplateIn with all fields", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		exercises := []TemplateExercise{
			{
				ID:            "exercise1",
				ExerciseID:    "push_up",
				ExerciseOrder: 1,
				Sets: []Set{
					{
						ID:        "set1",
						Completed: true,
						Weight:    0.0,
						Reps:      20,
					},
				},
			},
			{
				ID:            "exercise2",
				ExerciseID:    "pull_up",
				ExerciseOrder: 2,
				Sets: []Set{
					{
						ID:        "set2",
						Completed: false,
						Weight:    0.0,
						Reps:      10,
					},
				},
			},
		}

		templateIn := TemplateIn{
			ID:        id,
			Name:      "Upper Body Template",
			Order:     1,
			Exercises: exercises,
		}

		assert.Equal(t, id, templateIn.ID)
		assert.Equal(t, "Upper Body Template", templateIn.Name)
		assert.Equal(t, 1, templateIn.Order)
		assert.Len(t, templateIn.Exercises, 2)
		assert.Equal(t, "push_up", templateIn.Exercises[0].ExerciseID)
		assert.Equal(t, "exercise1", templateIn.Exercises[0].ID)
		assert.Equal(t, "pull_up", templateIn.Exercises[1].ExerciseID)
		assert.Equal(t, "exercise2", templateIn.Exercises[1].ID)
	})

	t.Run("TemplateIn with minimal fields", func(t *testing.T) {
		templateIn := TemplateIn{
			Name: "Minimal Template",
		}

		assert.Equal(t, "", templateIn.ID)
		assert.Equal(t, "Minimal Template", templateIn.Name)
		assert.Equal(t, 0, templateIn.Order)
		assert.Len(t, templateIn.Exercises, 0)
	})

	t.Run("TemplateIn with empty name", func(t *testing.T) {
		templateIn := TemplateIn{
			ID:    "2025-07-18T05:40:48.329406Z",
			Name:  "",
			Order: 5,
			Exercises: []TemplateExercise{
				{
					ID:            "exercise1",
					ExerciseID:    "test_exercise",
					ExerciseOrder: 1,
					Sets:          []Set{},
				},
			},
		}

		assert.Equal(t, "2025-07-18T05:40:48.329406Z", templateIn.ID)
		assert.Equal(t, "", templateIn.Name)
		assert.Equal(t, 5, templateIn.Order)
		assert.Len(t, templateIn.Exercises, 1)
		assert.Equal(t, "exercise1", templateIn.Exercises[0].ID)
	})

	t.Run("TemplateIn with empty ID", func(t *testing.T) {
		templateIn := TemplateIn{
			ID:   "",
			Name: "Template with Empty ID",
		}

		assert.Equal(t, "", templateIn.ID)
		assert.Equal(t, "Template with Empty ID", templateIn.Name)
	})
}

func TestNewTemplate(t *testing.T) {
	t.Run("Create template from TemplateIn with exercises", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		exercises := []TemplateExercise{
			{
				ID:            "exercise1",
				ExerciseID:    "squat",
				ExerciseOrder: 1,
				Sets: []Set{
					{
						ID:        "set1",
						Completed: true,
						Weight:    80.0,
						Reps:      12,
					},
					{
						ID:        "set2",
						Completed: false,
						Weight:    85.0,
						Reps:      10,
					},
				},
			},
			{
				ID:            "exercise2",
				ExerciseID:    "deadlift",
				ExerciseOrder: 2,
				Sets: []Set{
					{
						ID:        "set3",
						Completed: true,
						Weight:    120.0,
						Reps:      8,
					},
				},
			},
		}

		templateIn := &TemplateIn{
			ID:        id,
			Name:      "Leg Day",
			Order:     2,
			Exercises: exercises,
		}

		result := NewTemplate(templateIn, "user123")

		assert.Equal(t, "Leg Day", result.Name)
		assert.Equal(t, "user123", result.UserID())
		assert.Equal(t, UserKey+"user123", result.PK)
		assert.Equal(t, TemplateKey+id, result.SK)
		assert.Equal(t, 2, result.OrderInParent)
		assert.Len(t, result.Exercises, 2)

		// Check first exercise
		assert.Equal(t, "exercise1", result.Exercises[0].ID)
		assert.Equal(t, "squat", result.Exercises[0].ExerciseID)
		assert.Equal(t, 1, result.Exercises[0].ExerciseOrder)
		assert.Len(t, result.Exercises[0].Sets, 2)
		assert.Equal(t, "set1", result.Exercises[0].Sets[0].ID)
		assert.Equal(t, "set2", result.Exercises[0].Sets[1].ID)

		// Check second exercise
		assert.Equal(t, "exercise2", result.Exercises[1].ID)
		assert.Equal(t, "deadlift", result.Exercises[1].ExerciseID)
		assert.Equal(t, 2, result.Exercises[1].ExerciseOrder)
		assert.Len(t, result.Exercises[1].Sets, 1)
		assert.Equal(t, "set3", result.Exercises[1].Sets[0].ID)
	})

	t.Run("Create template from TemplateIn with no exercises", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		templateIn := &TemplateIn{
			ID:        id,
			Name:      "Empty Template",
			Order:     1,
			Exercises: []TemplateExercise{},
		}

		result := NewTemplate(templateIn, "user456")

		assert.Equal(t, "Empty Template", result.Name)
		assert.Equal(t, "user456", result.UserID())
		assert.Equal(t, UserKey+"user456", result.PK)
		assert.Equal(t, TemplateKey+id, result.SK)
		assert.Equal(t, 1, result.OrderInParent)
		assert.Len(t, result.Exercises, 0)
	})

	t.Run("Create template from TemplateIn with nil exercises", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		templateIn := &TemplateIn{
			ID:        id,
			Name:      "Nil Exercises Template",
			Order:     3,
			Exercises: nil,
		}

		result := NewTemplate(templateIn, "user789")

		assert.Equal(t, "Nil Exercises Template", result.Name)
		assert.Equal(t, "user789", result.UserID())
		assert.Equal(t, UserKey+"user789", result.PK)
		assert.Equal(t, TemplateKey+id, result.SK)
		assert.Equal(t, 3, result.OrderInParent)
		assert.Nil(t, result.Exercises)
	})

	t.Run("Create template with empty user ID", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		templateIn := &TemplateIn{
			ID:   id,
			Name: "Template with Empty User",
		}

		result := NewTemplate(templateIn, "")

		assert.Equal(t, "Template with Empty User", result.Name)
		assert.Equal(t, "", result.UserID())
		assert.Equal(t, UserKey, result.PK)
		assert.Equal(t, TemplateKey+id, result.SK)
	})

	t.Run("Create template with empty ID", func(t *testing.T) {
		templateIn := &TemplateIn{
			ID:   "",
			Name: "Template with Empty ID",
		}

		result := NewTemplate(templateIn, "user123")

		assert.Equal(t, "Template with Empty ID", result.Name)
		assert.Equal(t, "user123", result.UserID())
		assert.Equal(t, UserKey+"user123", result.PK)
		assert.Equal(t, TemplateKey, result.SK)
	})
}

func TestTemplateOut_StructFields(t *testing.T) {
	t.Run("TemplateOut with all fields", func(t *testing.T) {
		exercises := []TemplateExercise{
			{
				ID:            "exercise1",
				ExerciseID:    "bench_press",
				ExerciseOrder: 1,
				Sets: []Set{
					{
						ID:        "set1",
						Completed: true,
						Weight:    100.0,
						Reps:      8,
					},
				},
			},
		}

		templateOut := TemplateOut{
			ID:        "2025-07-18T05:40:48.329406Z",
			Name:      "Chest Workout",
			Order:     1,
			Exercises: exercises,
		}

		assert.Equal(t, "2025-07-18T05:40:48.329406Z", templateOut.ID)
		assert.Equal(t, "Chest Workout", templateOut.Name)
		assert.Equal(t, 1, templateOut.Order)
		assert.Len(t, templateOut.Exercises, 1)
		assert.Equal(t, "bench_press", templateOut.Exercises[0].ExerciseID)
		assert.Equal(t, "exercise1", templateOut.Exercises[0].ID)
	})

	t.Run("TemplateOut with zero values", func(t *testing.T) {
		templateOut := TemplateOut{}

		assert.Equal(t, "", templateOut.ID)
		assert.Equal(t, "", templateOut.Name)
		assert.Equal(t, 0, templateOut.Order)
		assert.Len(t, templateOut.Exercises, 0)
	})

	t.Run("TemplateOut with empty exercises slice", func(t *testing.T) {
		templateOut := TemplateOut{
			ID:        "2025-07-18T05:40:48.329406Z",
			Name:      "Empty Template",
			Order:     1,
			Exercises: []TemplateExercise{},
		}

		assert.Equal(t, "2025-07-18T05:40:48.329406Z", templateOut.ID)
		assert.Equal(t, "Empty Template", templateOut.Name)
		assert.Equal(t, 1, templateOut.Order)
		assert.Len(t, templateOut.Exercises, 0)
	})
}

func TestNewTemplateOut(t *testing.T) {
	t.Run("Create TemplateOut from Template with exercises", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		exercises := []TemplateExercise{
			{
				ID:            "exercise1",
				ExerciseID:    "push_up",
				ExerciseOrder: 1,
				Sets: []Set{
					{
						ID:        "set1",
						Completed: true,
						Weight:    0.0,
						Reps:      15,
					},
				},
			},
			{
				ID:            "exercise2",
				ExerciseID:    "dip",
				ExerciseOrder: 2,
				Sets: []Set{
					{
						ID:        "set2",
						Completed: false,
						Weight:    0.0,
						Reps:      12,
					},
				},
			},
		}

		template := &Template{
			Name:          "Upper Body",
			PK:            UserKey + "user123",
			SK:            TemplateKey + id,
			OrderInParent: 2,
			Exercises:     exercises,
		}

		result := NewTemplateOut(template)

		assert.Equal(t, id, result.ID)
		assert.Equal(t, "Upper Body", result.Name)
		assert.Equal(t, 2, result.Order)
		assert.Len(t, result.Exercises, 2)

		// Check exercises are preserved
		assert.Equal(t, "exercise1", result.Exercises[0].ID)
		assert.Equal(t, "push_up", result.Exercises[0].ExerciseID)
		assert.Equal(t, 1, result.Exercises[0].ExerciseOrder)
		assert.Len(t, result.Exercises[0].Sets, 1)
		assert.Equal(t, "set1", result.Exercises[0].Sets[0].ID)

		assert.Equal(t, "exercise2", result.Exercises[1].ID)
		assert.Equal(t, "dip", result.Exercises[1].ExerciseID)
		assert.Equal(t, 2, result.Exercises[1].ExerciseOrder)
		assert.Len(t, result.Exercises[1].Sets, 1)
		assert.Equal(t, "set2", result.Exercises[1].Sets[0].ID)
	})

	t.Run("Create TemplateOut from Template with no exercises", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		template := &Template{
			Name:          "Empty Template",
			PK:            UserKey + "user456",
			SK:            TemplateKey + id,
			OrderInParent: 1,
			Exercises:     []TemplateExercise{},
		}

		result := NewTemplateOut(template)

		assert.Equal(t, id, result.ID)
		assert.Equal(t, "Empty Template", result.Name)
		assert.Equal(t, 1, result.Order)
		assert.Len(t, result.Exercises, 0)
	})

	t.Run("Create TemplateOut from Template with nil exercises", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		template := &Template{
			Name:          "Nil Exercises Template",
			PK:            UserKey + "user789",
			SK:            TemplateKey + id,
			OrderInParent: 0,
			Exercises:     nil,
		}

		result := NewTemplateOut(template)

		assert.Equal(t, id, result.ID)
		assert.Equal(t, "Nil Exercises Template", result.Name)
		assert.Equal(t, 0, result.Order)
		assert.Nil(t, result.Exercises)
	})

	t.Run("Template ID extraction from SK", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		template := &Template{
			Name:          "Test Template",
			PK:            UserKey + "user123",
			SK:            TemplateKey + id,
			OrderInParent: 1,
			Exercises:     []TemplateExercise{},
		}

		result := NewTemplateOut(template)

		// The ID should be extracted from SK by removing the TemplateKey prefix
		assert.Equal(t, id, result.ID)
	})
}

func TestTemplateResponse_StructFields(t *testing.T) {
	t.Run("TemplateResponse with templates", func(t *testing.T) {
		templates := []TemplateOut{
			{
				ID:    "1",
				Name:  "Template 1",
				Order: 1,
			},
			{
				ID:    "2",
				Name:  "Template 2",
				Order: 2,
			},
		}

		response := TemplateResponse{
			Templates: templates,
		}

		assert.Len(t, response.Templates, 2)
		assert.Equal(t, "Template 1", response.Templates[0].Name)
		assert.Equal(t, "Template 2", response.Templates[1].Name)
	})

	t.Run("TemplateResponse with empty templates", func(t *testing.T) {
		response := TemplateResponse{
			Templates: []TemplateOut{},
		}

		assert.Len(t, response.Templates, 0)
	})

	t.Run("TemplateResponse with nil templates", func(t *testing.T) {
		response := TemplateResponse{
			Templates: nil,
		}

		assert.Nil(t, response.Templates)
	})
}

func TestNewTemplateArray(t *testing.T) {
	t.Run("Create array from multiple templates", func(t *testing.T) {
		id1 := "2025-07-18T05:40:48.329406Z"
		id2 := "2025-07-18T05:41:48.329406Z"
		id3 := "2025-07-18T05:42:48.329406Z"

		templates := []Template{
			{
				Name:          "Template 1",
				PK:            UserKey + "user123",
				SK:            TemplateKey + id1,
				OrderInParent: 1,
				Exercises: []TemplateExercise{
					{
						ID:            "exercise1",
						ExerciseID:    "push_up",
						ExerciseOrder: 1,
						Sets: []Set{
							{
								ID:        "set1",
								Completed: true,
								Weight:    0.0,
								Reps:      10,
							},
						},
					},
				},
			},
			{
				Name:          "Template 2",
				PK:            UserKey + "user123",
				SK:            TemplateKey + id2,
				OrderInParent: 2,
				Exercises:     []TemplateExercise{},
			},
			{
				Name:          "Template 3",
				PK:            UserKey + "user456",
				SK:            TemplateKey + id3,
				OrderInParent: 1,
				Exercises: []TemplateExercise{
					{
						ID:            "exercise2",
						ExerciseID:    "squat",
						ExerciseOrder: 1,
						Sets: []Set{
							{
								ID:        "set2",
								Completed: false,
								Weight:    60.0,
								Reps:      12,
							},
						},
					},
					{
						ID:            "exercise3",
						ExerciseID:    "deadlift",
						ExerciseOrder: 2,
						Sets: []Set{
							{
								ID:        "set3",
								Completed: true,
								Weight:    100.0,
								Reps:      8,
							},
						},
					},
				},
			},
		}

		result := NewTemplateArray(templates)

		assert.Len(t, result, 3)

		// Check first template
		assert.Equal(t, id1, result[0].ID)
		assert.Equal(t, "Template 1", result[0].Name)
		assert.Equal(t, 1, result[0].Order)
		assert.Len(t, result[0].Exercises, 1)
		assert.Equal(t, "exercise1", result[0].Exercises[0].ID)
		assert.Equal(t, "push_up", result[0].Exercises[0].ExerciseID)

		// Check second template
		assert.Equal(t, id2, result[1].ID)
		assert.Equal(t, "Template 2", result[1].Name)
		assert.Equal(t, 2, result[1].Order)
		assert.Len(t, result[1].Exercises, 0)

		// Check third template
		assert.Equal(t, id3, result[2].ID)
		assert.Equal(t, "Template 3", result[2].Name)
		assert.Equal(t, 1, result[2].Order)
		assert.Len(t, result[2].Exercises, 2)
		assert.Equal(t, "exercise2", result[2].Exercises[0].ID)
		assert.Equal(t, "squat", result[2].Exercises[0].ExerciseID)
		assert.Equal(t, "exercise3", result[2].Exercises[1].ID)
		assert.Equal(t, "deadlift", result[2].Exercises[1].ExerciseID)
	})

	t.Run("Create array from empty templates", func(t *testing.T) {
		templates := []Template{}
		result := NewTemplateArray(templates)

		assert.Len(t, result, 0)
	})

	t.Run("Create array from single template", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		templates := []Template{
			{
				Name:          "Single Template",
				PK:            UserKey + "user123",
				SK:            TemplateKey + id,
				OrderInParent: 1,
				Exercises: []TemplateExercise{
					{
						ID:            "exercise1",
						ExerciseID:    "plank",
						ExerciseOrder: 1,
						Sets: []Set{
							{
								ID:        "set1",
								Completed: true,
								Weight:    0.0,
								Reps:      0,
								Duration:  60.0,
							},
						},
					},
				},
			},
		}

		result := NewTemplateArray(templates)

		assert.Len(t, result, 1)
		assert.Equal(t, id, result[0].ID)
		assert.Equal(t, "Single Template", result[0].Name)
		assert.Equal(t, 1, result[0].Order)
		assert.Len(t, result[0].Exercises, 1)
		assert.Equal(t, "exercise1", result[0].Exercises[0].ID)
		assert.Equal(t, "plank", result[0].Exercises[0].ExerciseID)
	})
}

func TestTemplateExercise_WithComplexSets(t *testing.T) {
	t.Run("TemplateExercise with mixed set types", func(t *testing.T) {
		exercise := TemplateExercise{
			ID:            "exercise1",
			ExerciseID:    "compound_exercise",
			ExerciseOrder: 1,
			Sets: []Set{
				// Strength set
				{
					ID:        "set1",
					Completed: true,
					Weight:    100.0,
					Reps:      8,
					Duration:  0.0,
					Distance:  0.0,
				},
				// Cardio set
				{
					ID:        "set2",
					Completed: false,
					Weight:    0.0,
					Reps:      0,
					Duration:  300.0, // 5 minutes
					Distance:  1.0,   // 1 km
				},
				// Bodyweight set
				{
					ID:        "set3",
					Completed: true,
					Weight:    0.0,
					Reps:      20,
					Duration:  0.0,
					Distance:  0.0,
				},
			},
		}

		assert.Equal(t, "exercise1", exercise.ID)
		assert.Equal(t, "compound_exercise", exercise.ExerciseID)
		assert.Equal(t, 1, exercise.ExerciseOrder)
		assert.Len(t, exercise.Sets, 3)

		// Check strength set
		assert.Equal(t, "set1", exercise.Sets[0].ID)
		assert.True(t, exercise.Sets[0].Completed)
		assert.Equal(t, 100.0, exercise.Sets[0].Weight)
		assert.Equal(t, 8, exercise.Sets[0].Reps)

		// Check cardio set
		assert.Equal(t, "set2", exercise.Sets[1].ID)
		assert.False(t, exercise.Sets[1].Completed)
		assert.Equal(t, 0.0, exercise.Sets[1].Weight)
		assert.Equal(t, 0, exercise.Sets[1].Reps)
		assert.Equal(t, 300.0, exercise.Sets[1].Duration)
		assert.Equal(t, 1.0, exercise.Sets[1].Distance)

		// Check bodyweight set
		assert.Equal(t, "set3", exercise.Sets[2].ID)
		assert.True(t, exercise.Sets[2].Completed)
		assert.Equal(t, 0.0, exercise.Sets[2].Weight)
		assert.Equal(t, 20, exercise.Sets[2].Reps)
	})
}

func TestTemplate_EdgeCases(t *testing.T) {
	t.Run("Template with very long name", func(t *testing.T) {
		longName := "This is a very long template name that might be used in some edge cases where users input extremely long names for their workout templates"

		template := Template{
			Name: longName,
			PK:   UserKey + "user123",
		}

		assert.Equal(t, longName, template.Name)
		assert.Equal(t, "user123", template.UserID())
	})

	t.Run("Template with negative order", func(t *testing.T) {
		template := Template{
			Name:          "Negative Order Template",
			PK:            UserKey + "user123",
			OrderInParent: -1,
		}

		assert.Equal(t, "Negative Order Template", template.Name)
		assert.Equal(t, -1, template.OrderInParent)
	})

	t.Run("Template with large order number", func(t *testing.T) {
		template := Template{
			Name:          "Large Order Template",
			PK:            UserKey + "user123",
			OrderInParent: 999999,
		}

		assert.Equal(t, "Large Order Template", template.Name)
		assert.Equal(t, 999999, template.OrderInParent)
	})

	t.Run("Template with special characters in name", func(t *testing.T) {
		template := Template{
			Name: "Template with Special Characters: !@#$%^&*()",
			PK:   UserKey + "user123",
		}

		assert.Equal(t, "Template with Special Characters: !@#$%^&*()", template.Name)
		assert.Equal(t, "user123", template.UserID())
	})

	t.Run("TemplateExercise with negative order", func(t *testing.T) {
		exercise := TemplateExercise{
			ID:            "exercise1",
			ExerciseID:    "test_exercise",
			ExerciseOrder: -1,
			Sets:          []Set{},
		}

		assert.Equal(t, "exercise1", exercise.ID)
		assert.Equal(t, "test_exercise", exercise.ExerciseID)
		assert.Equal(t, -1, exercise.ExerciseOrder)
	})

	t.Run("TemplateExercise with large order number", func(t *testing.T) {
		exercise := TemplateExercise{
			ID:            "exercise1",
			ExerciseID:    "test_exercise",
			ExerciseOrder: 999999,
			Sets:          []Set{},
		}

		assert.Equal(t, "exercise1", exercise.ID)
		assert.Equal(t, "test_exercise", exercise.ExerciseID)
		assert.Equal(t, 999999, exercise.ExerciseOrder)
	})
}

func TestTemplateConstants(t *testing.T) {
	t.Run("Template uses correct constants", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		template := Template{
			PK: UserKey + "user123",
			SK: TemplateKey + id,
		}

		assert.Equal(t, "USER#user123", template.PK)
		assert.Equal(t, "TEMPLATE#"+id, template.SK)
		assert.Equal(t, "user123", template.UserID())
		assert.Equal(t, id, template.ID())
	})
}

func TestTemplateIn_WithComplexExercises(t *testing.T) {
	t.Run("TemplateIn with complex exercise structure", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		exercises := []TemplateExercise{
			{
				ID:            "exercise1",
				ExerciseID:    "superset_exercise",
				ExerciseOrder: 1,
				Sets: []Set{
					{
						ID:        "set1",
						Completed: true,
						Weight:    50.0,
						Reps:      12,
					},
					{
						ID:        "set2",
						Completed: false,
						Weight:    55.0,
						Reps:      10,
					},
				},
			},
			{
				ID:            "exercise2",
				ExerciseID:    "cardio_exercise",
				ExerciseOrder: 2,
				Sets: []Set{
					{
						ID:        "set3",
						Completed: true,
						Weight:    0.0,
						Reps:      0,
						Duration:  600.0, // 10 minutes
						Distance:  2.0,   // 2 km
					},
				},
			},
		}

		templateIn := TemplateIn{
			ID:        id,
			Name:      "Complex Template",
			Order:     1,
			Exercises: exercises,
		}

		assert.Equal(t, id, templateIn.ID)
		assert.Equal(t, "Complex Template", templateIn.Name)
		assert.Equal(t, 1, templateIn.Order)
		assert.Len(t, templateIn.Exercises, 2)

		// Check superset exercise
		assert.Equal(t, "exercise1", templateIn.Exercises[0].ID)
		assert.Equal(t, "superset_exercise", templateIn.Exercises[0].ExerciseID)
		assert.Len(t, templateIn.Exercises[0].Sets, 2)

		// Check cardio exercise
		assert.Equal(t, "exercise2", templateIn.Exercises[1].ID)
		assert.Equal(t, "cardio_exercise", templateIn.Exercises[1].ExerciseID)
		assert.Len(t, templateIn.Exercises[1].Sets, 1)
		assert.Equal(t, 600.0, templateIn.Exercises[1].Sets[0].Duration)
		assert.Equal(t, 2.0, templateIn.Exercises[1].Sets[0].Distance)
	})
}

func TestNewTemplate_EdgeCases(t *testing.T) {
	t.Run("NewTemplate with very long user ID", func(t *testing.T) {
		longUserId := "very_long_user_id_that_might_be_used_in_some_edge_cases_where_users_have_extremely_long_identifiers"
		id := "2025-07-18T05:40:48.329406Z"
		templateIn := &TemplateIn{
			ID:   id,
			Name: "Test Template",
		}

		result := NewTemplate(templateIn, longUserId)

		assert.Equal(t, longUserId, result.UserID())
		assert.Equal(t, UserKey+longUserId, result.PK)
		assert.Equal(t, TemplateKey+id, result.SK)
	})

	t.Run("NewTemplate with very long template ID", func(t *testing.T) {
		longId := "very_long_template_id_that_might_be_used_in_some_edge_cases_where_templates_have_extremely_long_identifiers"
		templateIn := &TemplateIn{
			ID:   longId,
			Name: "Test Template",
		}

		result := NewTemplate(templateIn, "user123")

		assert.Equal(t, longId, result.ID())
		assert.Equal(t, UserKey+"user123", result.PK)
		assert.Equal(t, TemplateKey+longId, result.SK)
	})
}
