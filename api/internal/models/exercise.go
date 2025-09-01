package models

import (
	"fmt"
	"net/url"
)

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
	Name         string            `json:"name" example:"Push Up" binding:"required"`
	Category     string            `json:"category" example:"Body weight" binding:"required"`
	Target       string            `json:"target" example:"Chest" binding:"required"`
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

type UserExerciseIn struct {
	Name         string  `dynamodbav:"name" json:"name" example:"Push Up" binding:"required"`
	Category     string  `dynamodbav:"category" json:"category" example:"Body weight" binding:"required"`
	Target       string  `dynamodbav:"target" json:"target" example:"Chest" binding:"required"`
	Instructions *string `dynamodbav:"instructions,omitempty" json:"instructions,omitempty" example:"Keep your body straight and lower yourself until your chest almost touches the ground."`
}

// @name UserExerciseIn

type UserExercise struct {
	UserExerciseIn
	PK string `json:"-" dynamodbav:"PK"`
	SK string `json:"-" dynamodbav:"SK"`
} // @name UserExercise

func NewUserExercise(e *UserExerciseIn, userId string) UserExercise {
	return UserExercise{
		PK:             fmt.Sprintf("%s%s", UserKey, userId),
		SK:             fmt.Sprintf("%s%s", ExerciseKey, url.PathEscape(e.Name)),
		UserExerciseIn: *e,
	}
}
