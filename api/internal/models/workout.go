package models

import (
	"fmt"
	"path"
	"strings"
	"time"
)

const (
	UserKey     = "USER#"
	WorkoutKey  = "WORKOUT#"
	TemplateKey = "TEMPLATE#"
	ExerciseKey = "EXERCISE#"
	ProgressKey = "PROGRESS#"
)

type Image struct {
	Key string `example:"workouts/abc/019b23cc-4de2-7a19-89a6-0960f4929e4c.png"`
}

func (i Image) Url(domain string) string {
	return fmt.Sprintf("%s/%s", domain, i.Key)
}

// ID parses the UUID from the key filename (without extension).
// Example: "workouts/abc/019b23cc-4de2-7a19-89a6-0960f4929e4c.png" -> UUID(...)
func (i Image) ID() string {
	base := path.Base(i.Key)             // "....png"
	ext := path.Ext(base)                // ".png"
	return strings.TrimSuffix(base, ext) // "<uuid>"
}

type ImageOut struct {
	Key       string `json:"key" example:"workouts/<workout>/<uuidv7>.png"`
	URL       string `json:"url" example:"https://<cdn-domain>/workouts/<workout>/<uuidv7>.png"`
	ID        string `json:"id" example:"019b23cc-4de2-7a19-89a6-0960f4929e4c"`
	WorkoutId string `json:"workoutId" example:"2025-07-25T18:20:01.253622Z"`
} // @name Image

type Workout struct {
	ID        string            `dynamodbav:"-"`  // todo delete
	UserID    string            `dynamodbav:"-"`  // todo delete
	PK        string            `dynamodbav:"PK"` // USER#<userID>
	SK        string            `dynamodbav:"SK"` // WORKOUT#<workoutID>
	Start     time.Time         `dynamodbav:"start"`
	End       *time.Time        `dynamodbav:"end,omitempty"`
	Name      string            `dynamodbav:"name,omitempty"`
	Exercises []WorkoutExercise `dynamodbav:"exercises"`
	ImageKeys *[]string         `dynamodbav:"images,omitempty" json:"-"`
}

func (w *Workout) String() string {
	return w.Name
}

type WorkoutExercise struct {
	ID            string `dynamodbav:"id"`
	ExerciseID    string `dynamodbav:"exercise_id"` // same as Exercise.Name
	ExerciseOrder int    `dynamodbav:"exercise_order"`
	Sets          []Set  `dynamodbav:"sets"`
}

type Set struct {
	ID        string  `dynamodbav:"id" json:"id" binding:"required" example:"2025-07-18T05:40:48.329406Z"`
	Completed bool    `dynamodbav:"completed" json:"completed" binding:"required" example:"true"`
	Weight    float64 `dynamodbav:"weight,omitempty" json:"weight,omitempty" example:"100"` // kg
	Reps      int     `dynamodbav:"reps,omitempty" json:"reps,omitempty" example:"10"`
	Duration  float64 `dynamodbav:"duration,omitempty" json:"duration,omitempty" example:"10"` // seconds
	Distance  float64 `dynamodbav:"distance,omitempty" json:"distance,omitempty" example:"10"` // kilometers
} // @name SetIn

type WorkoutExerciseIn struct {
	ID       string `json:"id" binding:"required" example:"2025-07-18T05:40:48.329406Z"`
	Exercise string `json:"exercise" binding:"required" example:"Push Up"`
	Sets     []Set  `json:"sets"`
	Order    int    `json:"order" example:"1"`
} // @name WorkoutExerciseIn

type WorkoutIn struct {
	ID        string              `json:"id" binding:"required" example:"2025-07-18T05:40:48.329406Z"`
	Name      string              `json:"name" example:"Legs"`
	Start     time.Time           `json:"start" binding:"required" example:"2023-01-01T12:00:00Z"`
	End       *time.Time          `json:"end,omitempty" example:"2023-01-01T12:00:00Z"`
	Exercises []WorkoutExerciseIn `json:"exercises" binding:"required"`
} // @name WorkoutIn

type SetOut struct {
	ID        string  `json:"id" binding:"required" example:"2025-07-18T05:40:48.329406Z"`
	Completed bool    `json:"completed" binding:"required" example:"true"`
	Weight    float64 `json:"weight" example:"100"`
	Reps      int     `json:"reps" example:"10"`
	Duration  float64 `json:"duration" example:"10"`
	Distance  float64 `json:"distance" example:"10"`
} // @name Set

type WorkoutExerciseOut struct {
	ID       string   `json:"id" example:"2025-07-18T05:40:48.329406Z"`
	Exercise *string  `json:"exercise" example:"Push Up"`
	Sets     []SetOut `json:"sets"`
} // @name WorkoutExercise

type WorkoutOut struct {
	ID        string               `json:"id" example:"2025-07-18T05:40:48.329406Z"`
	Name      string               `json:"name" example:"Legs"`
	Start     time.Time            `json:"start" example:"2023-01-01T12:00:00Z"`
	End       *time.Time           `json:"end" example:"2023-01-01T12:00:00Z"`
	Exercises []WorkoutExerciseOut `json:"exercises"`
	Images    *[]ImageOut          `json:"images"`
} // @name Workout

func NewSetOut(s *Set) SetOut {
	return SetOut{
		ID:        s.ID,
		Completed: s.Completed,
		Weight:    s.Weight,
		Reps:      s.Reps,
		Duration:  s.Duration,
		Distance:  s.Distance,
	}
}

func NewWorkoutExerciseOut(e *WorkoutExercise) WorkoutExerciseOut {
	sets := make([]SetOut, len(e.Sets))

	for i, s := range e.Sets {
		sets[i] = NewSetOut(&s)
	}

	return WorkoutExerciseOut{
		ID:       e.ID,
		Exercise: &e.ExerciseID,
		Sets:     sets,
	}
}

func NewWorkout(w *WorkoutIn, userId string) Workout {
	workout := Workout{
		ID:        w.ID,
		PK:        UserKey + userId,
		SK:        WorkoutKey + w.ID,
		Name:      w.Name,
		Start:     w.Start,
		End:       w.End,
		UserID:    userId,
		Exercises: make([]WorkoutExercise, len(w.Exercises)),
	}

	for i, exercise := range w.Exercises {
		workout.Exercises[i] = WorkoutExercise{
			ID:            exercise.ID,
			ExerciseID:    exercise.Exercise,
			ExerciseOrder: exercise.Order,
			Sets:          make([]Set, len(exercise.Sets)),
		}

		for j, set := range exercise.Sets {
			workout.Exercises[i].Sets[j] = Set{
				ID:        set.ID,
				Completed: set.Completed,
				Weight:    set.Weight,
				Reps:      set.Reps,
				Duration:  set.Duration,
				Distance:  set.Distance,
			}
		}
	}

	return workout
}

func NewWorkoutOut(w *Workout, mediaDomain string) WorkoutOut {
	exercises := make([]WorkoutExerciseOut, len(w.Exercises))

	for i, e := range w.Exercises {
		exercises[i] = NewWorkoutExerciseOut(&e)
	}

	var images []ImageOut

	if w.ImageKeys != nil {
		images = make([]ImageOut, 0, len(*w.ImageKeys))
		for _, k := range *w.ImageKeys {
			image := Image{Key: k}
			images = append(
				images,
				ImageOut{
					Key:       image.Key,
					URL:       image.Url(mediaDomain),
					ID:        image.ID(),
					WorkoutId: w.ID,
				},
			)
		}
	}

	return WorkoutOut{
		ID:        strings.TrimPrefix(w.SK, WorkoutKey),
		Name:      w.Name,
		Start:     w.Start,
		End:       w.End,
		Exercises: exercises,
		Images:    &images,
	}
}

type WorkoutResponse struct {
	Workouts []WorkoutOut `json:"workouts"`
	Cursor   string       `json:"cursor"`
} // @name WorkoutResponse

func NewWorkoutsArray(workouts []Workout, mediaDomain string) []WorkoutOut {
	workoutsOut := make([]WorkoutOut, len(workouts))
	for i, w := range workouts {
		workoutsOut[i] = NewWorkoutOut(&w, mediaDomain)
	}
	return workoutsOut
}

// ProgressImage is a DynamoDB item representing one progress photo entry.
// PK: USER#<userId>
// SK: PROGRESS#<workoutId>#<photoId>
type ProgressImage struct {
	PK        string  `dynamodbav:"PK" json:"-"`
	SK        string  `dynamodbav:"SK" json:"-"`
	WorkoutID string  `dynamodbav:"workout_id" json:"workoutId" example:"2025-07-25T18:20:01.253622Z"`
	PhotoID   string  `dynamodbav:"photo_id" json:"id" example:"2025-12-11T20:41:16.797Z~deadbeef"`
	Image     *string `dynamodbav:"image,omitempty" json:"url,omitempty" example:"https://<cdn-domain>/workouts/<hash>.jpg?v=<cache-bust>"`
	ImageKey  *string `dynamodbav:"image_key,omitempty" json:"key,omitempty" example:"workouts/<hash>.jpg"`
}

type ProgressGalleryResponse struct {
	Images []ProgressImage `json:"images"`
	Cursor *string         `json:"cursor"`
} // @name ProgressGalleryResponse

func ProgressCursorFromSK(sk string) string {
	// expects SK like: "PROGRESS#<workoutId>#<photoId>"
	return strings.TrimPrefix(sk, "PROGRESS#")
}
