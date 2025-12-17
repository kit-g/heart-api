package models

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestWorkout_StructFields(t *testing.T) {
	t.Run("Workout with all fields", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		userID := "user123"
		startTime := time.Now()
		endTime := startTime.Add(time.Hour)

		exercises := []WorkoutExercise{
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
		}

		workout := Workout{
			UserID:    userID,
			PK:        UserKey + userID,
			SK:        WorkoutKey + id,
			Start:     startTime,
			End:       &endTime,
			Name:      "Push Day",
			Exercises: exercises,
		}

		assert.Equal(t, id, workout.ID())
		assert.Equal(t, userID, workout.UserID)
		assert.Equal(t, UserKey+userID, workout.PK)
		assert.Equal(t, WorkoutKey+id, workout.SK)
		assert.Equal(t, startTime, workout.Start)
		assert.Equal(t, &endTime, workout.End)
		assert.Equal(t, "Push Day", workout.Name)
		assert.Len(t, workout.Exercises, 1)
		assert.Equal(t, "push_up", workout.Exercises[0].ExerciseID)
	})

	t.Run("Workout with minimal fields", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		startTime := time.Now()

		workout := Workout{
			Start: startTime,
			SK:    WorkoutKey + id,
		}

		assert.Equal(t, id, workout.ID())
		assert.Equal(t, startTime, workout.Start)
		assert.Nil(t, workout.End)
		assert.Equal(t, "", workout.Name)
		assert.Len(t, workout.Exercises, 0)
	})

	t.Run("Workout with no end time", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		startTime := time.Now()

		workout := Workout{
			UserID:    "user456",
			PK:        UserKey + "user456",
			SK:        WorkoutKey + id,
			Start:     startTime,
			End:       nil,
			Name:      "Ongoing Workout",
			Exercises: []WorkoutExercise{},
		}

		assert.Equal(t, id, workout.ID())
		assert.Equal(t, "user456", workout.UserID)
		assert.Equal(t, startTime, workout.Start)
		assert.Nil(t, workout.End)
		assert.Equal(t, "Ongoing Workout", workout.Name)
		assert.NotNil(t, workout.Exercises)
		assert.Len(t, workout.Exercises, 0)
	})
}

func TestWorkout_String(t *testing.T) {
	t.Run("Workout string representation", func(t *testing.T) {
		workout := Workout{
			Name: "Upper Body Workout",
		}

		assert.Equal(t, "Upper Body Workout", workout.String())
	})

	t.Run("Workout with empty name", func(t *testing.T) {
		workout := Workout{
			Name: "",
		}

		assert.Equal(t, "", workout.String())
	})
}

func TestWorkoutExercise_StructFields(t *testing.T) {
	t.Run("WorkoutExercise with multiple sets", func(t *testing.T) {
		sets := []Set{
			{
				ID:        "set1",
				Completed: true,
				Weight:    100.0,
				Reps:      10,
			},
			{
				ID:        "set2",
				Completed: false,
				Weight:    105.0,
				Reps:      8,
			},
		}

		exercise := WorkoutExercise{
			ID:            "exercise1",
			ExerciseID:    "bench_press",
			ExerciseOrder: 1,
			Sets:          sets,
		}

		assert.Equal(t, "exercise1", exercise.ID)
		assert.Equal(t, "bench_press", exercise.ExerciseID)
		assert.Equal(t, 1, exercise.ExerciseOrder)
		assert.Len(t, exercise.Sets, 2)
		assert.True(t, exercise.Sets[0].Completed)
		assert.Equal(t, 100.0, exercise.Sets[0].Weight)
		assert.Equal(t, 10, exercise.Sets[0].Reps)
		assert.False(t, exercise.Sets[1].Completed)
	})

	t.Run("WorkoutExercise with cardio sets", func(t *testing.T) {
		sets := []Set{
			{
				ID:        "set1",
				Completed: true,
				Weight:    0.0,
				Reps:      0,
				Duration:  1800.0, // 30 minutes
				Distance:  5.0,    // 5 km
			},
		}

		exercise := WorkoutExercise{
			ID:            "exercise2",
			ExerciseID:    "running",
			ExerciseOrder: 2,
			Sets:          sets,
		}

		assert.Equal(t, "exercise2", exercise.ID)
		assert.Equal(t, "running", exercise.ExerciseID)
		assert.Equal(t, 2, exercise.ExerciseOrder)
		assert.Len(t, exercise.Sets, 1)
		assert.True(t, exercise.Sets[0].Completed)
		assert.Equal(t, 0.0, exercise.Sets[0].Weight)
		assert.Equal(t, 0, exercise.Sets[0].Reps)
		assert.Equal(t, 1800.0, exercise.Sets[0].Duration)
		assert.Equal(t, 5.0, exercise.Sets[0].Distance)
	})

	t.Run("WorkoutExercise with no sets", func(t *testing.T) {
		exercise := WorkoutExercise{
			ID:            "exercise3",
			ExerciseID:    "plank",
			ExerciseOrder: 3,
			Sets:          []Set{},
		}

		assert.Equal(t, "exercise3", exercise.ID)
		assert.Equal(t, "plank", exercise.ExerciseID)
		assert.Equal(t, 3, exercise.ExerciseOrder)
		assert.Len(t, exercise.Sets, 0)
	})
}

func TestSet_StructFields(t *testing.T) {
	t.Run("Set with weight and reps", func(t *testing.T) {
		set := Set{
			ID:        "set1",
			Completed: true,
			Weight:    80.0,
			Reps:      12,
		}

		assert.Equal(t, "set1", set.ID)
		assert.True(t, set.Completed)
		assert.Equal(t, 80.0, set.Weight)
		assert.Equal(t, 12, set.Reps)
		assert.Equal(t, 0.0, set.Duration)
		assert.Equal(t, 0.0, set.Distance)
	})

	t.Run("Set with duration and distance", func(t *testing.T) {
		set := Set{
			ID:        "set2",
			Completed: false,
			Weight:    0.0,
			Reps:      0,
			Duration:  600.0, // 10 minutes
			Distance:  2.5,   // 2.5 km
		}

		assert.Equal(t, "set2", set.ID)
		assert.False(t, set.Completed)
		assert.Equal(t, 0.0, set.Weight)
		assert.Equal(t, 0, set.Reps)
		assert.Equal(t, 600.0, set.Duration)
		assert.Equal(t, 2.5, set.Distance)
	})

	t.Run("Set with all fields", func(t *testing.T) {
		set := Set{
			ID:        "set3",
			Completed: true,
			Weight:    50.0,
			Reps:      20,
			Duration:  300.0,
			Distance:  1.0,
		}

		assert.Equal(t, "set3", set.ID)
		assert.True(t, set.Completed)
		assert.Equal(t, 50.0, set.Weight)
		assert.Equal(t, 20, set.Reps)
		assert.Equal(t, 300.0, set.Duration)
		assert.Equal(t, 1.0, set.Distance)
	})

	t.Run("Set with empty ID", func(t *testing.T) {
		set := Set{
			ID:        "",
			Completed: false,
		}

		assert.Equal(t, "", set.ID)
		assert.False(t, set.Completed)
		assert.Equal(t, 0.0, set.Weight)
		assert.Equal(t, 0, set.Reps)
		assert.Equal(t, 0.0, set.Duration)
		assert.Equal(t, 0.0, set.Distance)
	})
}

func TestWorkoutExerciseIn_StructFields(t *testing.T) {
	t.Run("WorkoutExerciseIn with sets", func(t *testing.T) {
		sets := []Set{
			{
				ID:        "set1",
				Completed: true,
				Weight:    60.0,
				Reps:      12,
			},
			{
				ID:        "set2",
				Completed: false,
				Weight:    65.0,
				Reps:      10,
			},
		}

		exerciseIn := WorkoutExerciseIn{
			ID:       "exercise1",
			Exercise: "squat",
			Sets:     sets,
			Order:    1,
		}

		assert.Equal(t, "exercise1", exerciseIn.ID)
		assert.Equal(t, "squat", exerciseIn.Exercise)
		assert.Len(t, exerciseIn.Sets, 2)
		assert.Equal(t, 1, exerciseIn.Order)
		assert.True(t, exerciseIn.Sets[0].Completed)
		assert.Equal(t, 60.0, exerciseIn.Sets[0].Weight)
	})

	t.Run("WorkoutExerciseIn with no sets", func(t *testing.T) {
		exerciseIn := WorkoutExerciseIn{
			ID:       "exercise2",
			Exercise: "deadlift",
			Sets:     []Set{},
			Order:    2,
		}

		assert.Equal(t, "exercise2", exerciseIn.ID)
		assert.Equal(t, "deadlift", exerciseIn.Exercise)
		assert.Len(t, exerciseIn.Sets, 0)
		assert.Equal(t, 2, exerciseIn.Order)
	})
}

func TestWorkoutIn_StructFields(t *testing.T) {
	t.Run("WorkoutIn with all fields", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		startTime := time.Now()
		endTime := startTime.Add(time.Hour)

		exercises := []WorkoutExerciseIn{
			{
				ID:       "exercise1",
				Exercise: "push_up",
				Sets: []Set{
					{
						ID:        "set1",
						Completed: true,
						Weight:    0.0,
						Reps:      15,
					},
				},
				Order: 1,
			},
		}

		workoutIn := WorkoutIn{
			ID:        id,
			Name:      "Push Day",
			Start:     startTime,
			End:       &endTime,
			Exercises: exercises,
		}

		assert.Equal(t, id, workoutIn.ID)
		assert.Equal(t, "Push Day", workoutIn.Name)
		assert.Equal(t, startTime, workoutIn.Start)
		assert.Equal(t, &endTime, workoutIn.End)
		assert.Len(t, workoutIn.Exercises, 1)
		assert.Equal(t, "push_up", workoutIn.Exercises[0].Exercise)
	})

	t.Run("WorkoutIn with minimal fields", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		startTime := time.Now()

		workoutIn := WorkoutIn{
			ID:        id,
			Start:     startTime,
			Exercises: []WorkoutExerciseIn{},
		}

		assert.Equal(t, id, workoutIn.ID)
		assert.Equal(t, "", workoutIn.Name)
		assert.Equal(t, startTime, workoutIn.Start)
		assert.Nil(t, workoutIn.End)
		assert.Len(t, workoutIn.Exercises, 0)
	})
}

func TestNewWorkout(t *testing.T) {
	t.Run("Create workout from WorkoutIn with exercises", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		startTime := time.Now()
		endTime := startTime.Add(time.Hour)
		userID := "user123"

		exercises := []WorkoutExerciseIn{
			{
				ID:       "exercise1",
				Exercise: "squat",
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
				Order: 1,
			},
			{
				ID:       "exercise2",
				Exercise: "deadlift",
				Sets: []Set{
					{
						ID:        "set3",
						Completed: true,
						Weight:    120.0,
						Reps:      8,
					},
				},
				Order: 2,
			},
		}

		workoutIn := &WorkoutIn{
			ID:        id,
			Name:      "Leg Day",
			Start:     startTime,
			End:       &endTime,
			Exercises: exercises,
		}

		result := NewWorkout(workoutIn, userID)

		assert.Equal(t, id, result.ID())
		assert.Equal(t, userID, result.UserID)
		assert.Equal(t, UserKey+userID, result.PK)
		assert.Equal(t, WorkoutKey+id, result.SK)
		assert.Equal(t, "Leg Day", result.Name)
		assert.Equal(t, startTime, result.Start)
		assert.Equal(t, &endTime, result.End)
		assert.Len(t, result.Exercises, 2)

		// Check first exercise
		assert.Equal(t, "exercise1", result.Exercises[0].ID)
		assert.Equal(t, "squat", result.Exercises[0].ExerciseID)
		assert.Equal(t, 1, result.Exercises[0].ExerciseOrder)
		assert.Len(t, result.Exercises[0].Sets, 2)
		assert.Equal(t, "set1", result.Exercises[0].Sets[0].ID)
		assert.True(t, result.Exercises[0].Sets[0].Completed)
		assert.Equal(t, 80.0, result.Exercises[0].Sets[0].Weight)

		// Check second exercise
		assert.Equal(t, "exercise2", result.Exercises[1].ID)
		assert.Equal(t, "deadlift", result.Exercises[1].ExerciseID)
		assert.Equal(t, 2, result.Exercises[1].ExerciseOrder)
		assert.Len(t, result.Exercises[1].Sets, 1)
		assert.Equal(t, "set3", result.Exercises[1].Sets[0].ID)
		assert.True(t, result.Exercises[1].Sets[0].Completed)
		assert.Equal(t, 120.0, result.Exercises[1].Sets[0].Weight)
	})

	t.Run("Create workout from WorkoutIn with no exercises", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		startTime := time.Now()
		userID := "user456"

		workoutIn := &WorkoutIn{
			ID:        id,
			Name:      "Empty Workout",
			Start:     startTime,
			Exercises: []WorkoutExerciseIn{},
		}

		result := NewWorkout(workoutIn, userID)

		assert.Equal(t, id, result.ID())
		assert.Equal(t, userID, result.UserID)
		assert.Equal(t, "Empty Workout", result.Name)
		assert.Equal(t, startTime, result.Start)
		assert.Len(t, result.Exercises, 0)
	})

	t.Run("Create workout with empty user ID", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		startTime := time.Now()

		workoutIn := &WorkoutIn{
			ID:        id,
			Name:      "Workout with Empty User",
			Start:     startTime,
			Exercises: []WorkoutExerciseIn{},
		}

		result := NewWorkout(workoutIn, "")

		assert.Equal(t, id, result.ID())
		assert.Equal(t, "", result.UserID)
		assert.Equal(t, UserKey, result.PK)
		assert.Equal(t, WorkoutKey+id, result.SK)
	})
}

func TestSetOut_StructFields(t *testing.T) {
	t.Run("SetOut with all fields", func(t *testing.T) {
		setOut := SetOut{
			ID:        "set1",
			Completed: true,
			Weight:    90.0,
			Reps:      6,
			Duration:  180.0,
			Distance:  0.8,
		}

		assert.Equal(t, "set1", setOut.ID)
		assert.True(t, setOut.Completed)
		assert.Equal(t, 90.0, setOut.Weight)
		assert.Equal(t, 6, setOut.Reps)
		assert.Equal(t, 180.0, setOut.Duration)
		assert.Equal(t, 0.8, setOut.Distance)
	})
}

func TestWorkoutExerciseOut_StructFields(t *testing.T) {
	t.Run("WorkoutExerciseOut with sets", func(t *testing.T) {
		exerciseName := "bench_press"
		sets := []SetOut{
			{
				ID:        "set1",
				Completed: true,
				Weight:    100.0,
				Reps:      8,
			},
			{
				ID:        "set2",
				Completed: false,
				Weight:    105.0,
				Reps:      6,
			},
		}

		exerciseOut := WorkoutExerciseOut{
			ID:       "exercise1",
			Exercise: &exerciseName,
			Sets:     sets,
		}

		assert.Equal(t, "exercise1", exerciseOut.ID)
		assert.Equal(t, &exerciseName, exerciseOut.Exercise)
		assert.Len(t, exerciseOut.Sets, 2)
		assert.Equal(t, "set1", exerciseOut.Sets[0].ID)
		assert.True(t, exerciseOut.Sets[0].Completed)
	})

	t.Run("WorkoutExerciseOut with nil exercise", func(t *testing.T) {
		exerciseOut := WorkoutExerciseOut{
			ID:       "exercise1",
			Exercise: nil,
			Sets:     []SetOut{},
		}

		assert.Equal(t, "exercise1", exerciseOut.ID)
		assert.Nil(t, exerciseOut.Exercise)
		assert.Len(t, exerciseOut.Sets, 0)
	})
}

func TestWorkoutOut_StructFields(t *testing.T) {
	t.Run("WorkoutOut with all fields", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		startTime := time.Now()
		endTime := startTime.Add(time.Hour)
		exerciseName := "push_up"

		exercises := []WorkoutExerciseOut{
			{
				ID:       "exercise1",
				Exercise: &exerciseName,
				Sets: []SetOut{
					{
						ID:        "set1",
						Completed: true,
						Weight:    0.0,
						Reps:      15,
					},
				},
			},
		}

		workoutOut := WorkoutOut{
			ID:        id,
			Name:      "Push Day",
			Start:     startTime,
			End:       &endTime,
			Exercises: exercises,
		}

		assert.Equal(t, id, workoutOut.ID)
		assert.Equal(t, "Push Day", workoutOut.Name)
		assert.Equal(t, startTime, workoutOut.Start)
		assert.Equal(t, &endTime, workoutOut.End)
		assert.Len(t, workoutOut.Exercises, 1)
		assert.Equal(t, &exerciseName, workoutOut.Exercises[0].Exercise)
	})

	t.Run("WorkoutOut with minimal fields", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		startTime := time.Now()

		workoutOut := WorkoutOut{
			ID:        id,
			Start:     startTime,
			Exercises: []WorkoutExerciseOut{},
		}

		assert.Equal(t, id, workoutOut.ID)
		assert.Equal(t, "", workoutOut.Name)
		assert.Equal(t, startTime, workoutOut.Start)
		assert.Nil(t, workoutOut.End)
		assert.Len(t, workoutOut.Exercises, 0)
	})
}

func TestNewSetOut(t *testing.T) {
	t.Run("Create SetOut from Set with all fields", func(t *testing.T) {
		set := &Set{
			ID:        "set1",
			Completed: true,
			Weight:    85.0,
			Reps:      9,
			Duration:  240.0,
			Distance:  1.2,
		}

		result := NewSetOut(set)

		assert.Equal(t, "set1", result.ID)
		assert.True(t, result.Completed)
		assert.Equal(t, 85.0, result.Weight)
		assert.Equal(t, 9, result.Reps)
		assert.Equal(t, 240.0, result.Duration)
		assert.Equal(t, 1.2, result.Distance)
	})

	t.Run("Create SetOut from Set with minimal fields", func(t *testing.T) {
		set := &Set{
			ID:        "set2",
			Completed: false,
		}

		result := NewSetOut(set)

		assert.Equal(t, "set2", result.ID)
		assert.False(t, result.Completed)
		assert.Equal(t, 0.0, result.Weight)
		assert.Equal(t, 0, result.Reps)
		assert.Equal(t, 0.0, result.Duration)
		assert.Equal(t, 0.0, result.Distance)
	})

	t.Run("Create SetOut from Set with empty ID", func(t *testing.T) {
		set := &Set{
			ID:        "",
			Completed: true,
			Weight:    50.0,
			Reps:      10,
		}

		result := NewSetOut(set)

		assert.Equal(t, "", result.ID)
		assert.True(t, result.Completed)
		assert.Equal(t, 50.0, result.Weight)
		assert.Equal(t, 10, result.Reps)
	})
}

func TestNewWorkoutExerciseOut(t *testing.T) {
	t.Run("Create WorkoutExerciseOut from WorkoutExercise with sets", func(t *testing.T) {
		sets := []Set{
			{
				ID:        "set1",
				Completed: true,
				Weight:    70.0,
				Reps:      11,
			},
			{
				ID:        "set2",
				Completed: false,
				Weight:    75.0,
				Reps:      9,
			},
		}

		exercise := &WorkoutExercise{
			ID:            "exercise1",
			ExerciseID:    "pull_up",
			ExerciseOrder: 1,
			Sets:          sets,
		}

		result := NewWorkoutExerciseOut(exercise)

		assert.Equal(t, "exercise1", result.ID)
		assert.Equal(t, &exercise.ExerciseID, result.Exercise)
		assert.Len(t, result.Sets, 2)
		assert.Equal(t, "set1", result.Sets[0].ID)
		assert.True(t, result.Sets[0].Completed)
		assert.Equal(t, 70.0, result.Sets[0].Weight)
		assert.Equal(t, "set2", result.Sets[1].ID)
		assert.False(t, result.Sets[1].Completed)
	})

	t.Run("Create WorkoutExerciseOut from WorkoutExercise with no sets", func(t *testing.T) {
		exercise := &WorkoutExercise{
			ID:            "exercise2",
			ExerciseID:    "plank",
			ExerciseOrder: 2,
			Sets:          []Set{},
		}

		result := NewWorkoutExerciseOut(exercise)

		assert.Equal(t, "exercise2", result.ID)
		assert.Equal(t, &exercise.ExerciseID, result.Exercise)
		assert.Len(t, result.Sets, 0)
	})
}

func TestNewWorkoutOut(t *testing.T) {
	t.Run("Create WorkoutOut from Workout with exercises", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		startTime := time.Now()
		endTime := startTime.Add(time.Hour)

		exercises := []WorkoutExercise{
			{
				ID:            "exercise1",
				ExerciseID:    "squat",
				ExerciseOrder: 1,
				Sets: []Set{
					{
						ID:        "set1",
						Completed: true,
						Weight:    100.0,
						Reps:      10,
					},
				},
			},
		}

		workout := &Workout{
			PK:        UserKey + "user123",
			SK:        WorkoutKey + id,
			Name:      "Leg Day",
			Start:     startTime,
			End:       &endTime,
			Exercises: exercises,
		}

		result := NewWorkoutOut(workout, "https://images.com")

		assert.Equal(t, id, result.ID)
		assert.Equal(t, "Leg Day", result.Name)
		assert.Equal(t, startTime, result.Start)
		assert.Equal(t, &endTime, result.End)
		assert.Len(t, result.Exercises, 1)
		assert.Equal(t, "exercise1", result.Exercises[0].ID)
		assert.Equal(t, &exercises[0].ExerciseID, result.Exercises[0].Exercise)
		assert.Len(t, result.Exercises[0].Sets, 1)
		assert.Equal(t, "set1", result.Exercises[0].Sets[0].ID)
	})

	t.Run("Create WorkoutOut from Workout with no exercises", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		startTime := time.Now()

		workout := &Workout{
			PK:        UserKey + "user456",
			SK:        WorkoutKey + id,
			Name:      "Empty Workout",
			Start:     startTime,
			Exercises: []WorkoutExercise{},
		}

		result := NewWorkoutOut(workout, "https://images.com")

		assert.Equal(t, id, result.ID)
		assert.Equal(t, "Empty Workout", result.Name)
		assert.Equal(t, startTime, result.Start)
		assert.Nil(t, result.End)
		assert.Len(t, result.Exercises, 0)
	})

	t.Run("NewWorkoutOut extracts ID from SK correctly", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		startTime := time.Now()

		workout := &Workout{
			PK:        UserKey + "user123",
			SK:        WorkoutKey + id,
			Name:      "Test Workout",
			Start:     startTime,
			Exercises: []WorkoutExercise{},
		}

		result := NewWorkoutOut(workout, "https://images.com")

		// The ID should be extracted from SK by removing the WorkoutKey prefix
		assert.Equal(t, id, result.ID)
	})
}

func TestWorkoutResponse_StructFields(t *testing.T) {
	t.Run("WorkoutResponse with workouts and cursor", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		startTime := time.Now()

		workouts := []WorkoutOut{
			{
				ID:        id,
				Name:      "Workout 1",
				Start:     startTime,
				Exercises: []WorkoutExerciseOut{},
			},
		}

		response := WorkoutResponse{
			Workouts: workouts,
			Cursor:   "next_cursor",
		}

		assert.Len(t, response.Workouts, 1)
		assert.Equal(t, "Workout 1", response.Workouts[0].Name)
		assert.Equal(t, "next_cursor", response.Cursor)
	})

	t.Run("WorkoutResponse with empty workouts", func(t *testing.T) {
		response := WorkoutResponse{
			Workouts: []WorkoutOut{},
			Cursor:   "",
		}

		assert.Len(t, response.Workouts, 0)
		assert.Equal(t, "", response.Cursor)
	})
}

func TestNewWorkoutsArray(t *testing.T) {
	t.Run("Create array from multiple workouts", func(t *testing.T) {
		id1 := "2025-07-18T05:40:48.329406Z"
		id2 := "2025-07-18T05:41:48.329406Z"
		startTime := time.Now()

		workouts := []Workout{
			{
				PK:    UserKey + "user123",
				SK:    WorkoutKey + id1,
				Name:  "Workout 1",
				Start: startTime,
				Exercises: []WorkoutExercise{
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
				},
			},
			{
				PK:        UserKey + "user123",
				SK:        WorkoutKey + id2,
				Name:      "Workout 2",
				Start:     startTime,
				Exercises: []WorkoutExercise{},
			},
		}

		result := NewWorkoutsArray(workouts, "https://images.com")

		assert.Len(t, result, 2)
		assert.Equal(t, id1, result[0].ID)
		assert.Equal(t, "Workout 1", result[0].Name)
		assert.Len(t, result[0].Exercises, 1)
		assert.Equal(t, id2, result[1].ID)
		assert.Equal(t, "Workout 2", result[1].Name)
		assert.Len(t, result[1].Exercises, 0)
	})

	t.Run("Create array from empty workouts", func(t *testing.T) {
		workouts := []Workout{}
		result := NewWorkoutsArray(workouts, "https://images.com")

		assert.Len(t, result, 0)
	})

	t.Run("Create array from single workout", func(t *testing.T) {
		id := "2025-07-18T05:40:48.329406Z"
		startTime := time.Now()

		workouts := []Workout{
			{
				PK:        UserKey + "user123",
				SK:        WorkoutKey + id,
				Name:      "Single Workout",
				Start:     startTime,
				Exercises: []WorkoutExercise{},
			},
		}

		result := NewWorkoutsArray(workouts, "https://images.com")

		assert.Len(t, result, 1)
		assert.Equal(t, id, result[0].ID)
		assert.Equal(t, "Single Workout", result[0].Name)
	})
}

func TestWorkoutExercise_WithMixedSets(t *testing.T) {
	t.Run("WorkoutExercise with mixed set types", func(t *testing.T) {
		exercise := WorkoutExercise{
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

func TestWorkout_EdgeCases(t *testing.T) {
	t.Run("Workout with very long name", func(t *testing.T) {
		longName := "This is a very long workout name that might be used in some edge cases where users input extremely long names for their workouts"
		startTime := time.Now()

		workout := Workout{
			Name:  longName,
			Start: startTime,
		}

		assert.Equal(t, longName, workout.Name)
		assert.Equal(t, longName, workout.String())
	})

	t.Run("Workout with negative exercise order", func(t *testing.T) {
		exercise := WorkoutExercise{
			ID:            "exercise1",
			ExerciseID:    "test_exercise",
			ExerciseOrder: -1,
			Sets:          []Set{},
		}

		assert.Equal(t, "exercise1", exercise.ID)
		assert.Equal(t, "test_exercise", exercise.ExerciseID)
		assert.Equal(t, -1, exercise.ExerciseOrder)
	})

	t.Run("Workout with large exercise order", func(t *testing.T) {
		exercise := WorkoutExercise{
			ID:            "exercise1",
			ExerciseID:    "test_exercise",
			ExerciseOrder: 999999,
			Sets:          []Set{},
		}

		assert.Equal(t, "exercise1", exercise.ID)
		assert.Equal(t, "test_exercise", exercise.ExerciseID)
		assert.Equal(t, 999999, exercise.ExerciseOrder)
	})

	t.Run("Set with negative values", func(t *testing.T) {
		set := Set{
			ID:        "set1",
			Completed: true,
			Weight:    -50.0,
			Reps:      -10,
			Duration:  -100.0,
			Distance:  -5.0,
		}

		assert.Equal(t, "set1", set.ID)
		assert.True(t, set.Completed)
		assert.Equal(t, -50.0, set.Weight)
		assert.Equal(t, -10, set.Reps)
		assert.Equal(t, -100.0, set.Duration)
		assert.Equal(t, -5.0, set.Distance)
	})
}

func TestWorkoutConstants(t *testing.T) {
	t.Run("Check workout constants", func(t *testing.T) {
		assert.Equal(t, "USER#", UserKey)
		assert.Equal(t, "WORKOUT#", WorkoutKey)
		assert.Equal(t, "TEMPLATE#", TemplateKey)
		assert.Equal(t, "PROGRESS#", ProgressKey)
	})
}

func TestProgressImage_StructFields(t *testing.T) {
	t.Run("ProgressImage with all fields", func(t *testing.T) {
		imageURL := "https://example.com/workouts/img.jpg?v=2025-12-11T20:41:16.797Z"
		imageKey := "workouts/abcd1234.jpg"

		p := ProgressImage{
			PK:        UserKey + "user123",
			SK:        ProgressKey + "2025-07-25T18:20:01.253622Z#2025-12-11T20:41:16.797Z~deadbeef",
			WorkoutID: "2025-07-25T18:20:01.253622Z",
			PhotoID:   "2025-12-11T20:41:16.797Z~deadbeef",
			Image:     &imageURL,
			ImageKey:  &imageKey,
		}

		assert.Equal(t, UserKey+"user123", p.PK)
		assert.Equal(t, ProgressKey+"2025-07-25T18:20:01.253622Z#2025-12-11T20:41:16.797Z~deadbeef", p.SK)
		assert.Equal(t, "2025-07-25T18:20:01.253622Z", p.WorkoutID)
		assert.Equal(t, "2025-12-11T20:41:16.797Z~deadbeef", p.PhotoID)
		assert.NotNil(t, p.Image)
		assert.Equal(t, imageURL, *p.Image)
		assert.NotNil(t, p.ImageKey)
		assert.Equal(t, imageKey, *p.ImageKey)
	})

	t.Run("ProgressImage with optional fields nil", func(t *testing.T) {
		p := ProgressImage{
			PK:        UserKey + "user456",
			SK:        ProgressKey + "2025-07-25T18:20:01.253622Z#2025-12-11T20:41:16.797Z~beadfeed",
			WorkoutID: "2025-07-25T18:20:01.253622Z",
			PhotoID:   "2025-12-11T20:41:16.797Z~beadfeed",
			Image:     nil,
			ImageKey:  nil,
		}

		assert.Equal(t, UserKey+"user456", p.PK)
		assert.Equal(t, "2025-07-25T18:20:01.253622Z", p.WorkoutID)
		assert.Equal(t, "2025-12-11T20:41:16.797Z~beadfeed", p.PhotoID)
		assert.Nil(t, p.Image)
		assert.Nil(t, p.ImageKey)
	})
}

func TestProgressGalleryResponse_CursorNullable(t *testing.T) {
	t.Run("Cursor nil", func(t *testing.T) {
		resp := ProgressGalleryResponse{
			Images: []ImageOut{},
			Cursor: nil,
		}

		assert.NotNil(t, resp.Images)
		assert.Len(t, resp.Images, 0)
		assert.Nil(t, resp.Cursor)
	})

	t.Run("Cursor present", func(t *testing.T) {
		cursor := "2025-07-25T18:20:01.253622Z#2025-12-11T20:41:16.797Z~deadbeef"
		resp := ProgressGalleryResponse{
			Images: []ImageOut{
				{
					WorkoutId: "2025-07-25T18:20:01.253622Z",
					Key:       "workouts/2025-12-11T20:41:16.797Z~deadbeef",
				},
			},
			Cursor: &cursor,
		}

		assert.Len(t, resp.Images, 1)
		assert.NotNil(t, resp.Cursor)
		assert.Equal(t, cursor, *resp.Cursor)
	})
}

func TestProgressCursorFromSK(t *testing.T) {
	t.Run("Trims PROGRESS# prefix", func(t *testing.T) {
		sk := ProgressKey + "2025-07-25T18:20:01.253622Z#2025-12-11T20:41:16.797Z~deadbeef"
		out := ProgressCursorFromSK(sk)

		assert.Equal(t, "2025-07-25T18:20:01.253622Z#2025-12-11T20:41:16.797Z~deadbeef", out)
	})

	t.Run("No prefix present returns original string", func(t *testing.T) {
		sk := "NOTPROGRESS#whatever"
		out := ProgressCursorFromSK(sk)

		assert.Equal(t, sk, out)
	})
}

func TestProgressModels_ZeroValues(t *testing.T) {
	t.Run("Zero values", func(t *testing.T) {
		var p ProgressImage
		var r ProgressGalleryResponse

		assert.Equal(t, "", p.PK)
		assert.Equal(t, "", p.SK)
		assert.Equal(t, "", p.WorkoutID)
		assert.Equal(t, "", p.PhotoID)
		assert.Nil(t, p.Image)
		assert.Nil(t, p.ImageKey)

		// slice zero-value is nil; cursor should also be nil
		assert.Nil(t, r.Images)
		assert.Nil(t, r.Cursor)
	})
}
