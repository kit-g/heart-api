package models

type Exercise struct {
	PK           string            `dynamodbav:"pk"` // always "EXERCISE"
	Name         string            `dynamodbav:"sk"`
	Category     string            `dynamodbav:"category"`
	Target       string            `dynamodbav:"target"`
	Asset        *ImageDescription `dynamodbav:"asset,omitempty"`
	Thumbnail    *ImageDescription `dynamodbav:"thumbnail,omitempty"`
	Instructions *string           `dynamodbav:"instructions,omitempty"`
	UserID       string            `dynamodbav:"userId,omitempty"`
}

func (e *Exercise) String() string {
	return e.Name
}

type ExerciseOut struct {
	Name         string            `json:"name" example:"Push Up"`
	Category     string            `json:"category" example:"Body weight"`
	Target       string            `json:"target" example:"Chest"`
	Asset        *ImageDescription `json:"asset,omitempty"`
	Thumbnail    *ImageDescription `json:"thumbnail,omitempty"`
	Instructions *string           `json:"instructions,omitempty" example:"Keep your body straight and lower yourself until your chest almost touches the ground."`
} // @name Exercise

func NewExerciseOut(e *Exercise) ExerciseOut {
	return ExerciseOut{
		Name:         e.Name,
		Category:     e.Category,
		Target:       e.Target,
		Asset:        e.Asset,
		Thumbnail:    e.Thumbnail,
		Instructions: e.Instructions,
	}
}

type ExercisesResponse struct {
	Exercises []ExerciseOut `json:"exercises"`
} // @name ExercisesResponse
