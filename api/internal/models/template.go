package models

import (
	"fmt"
	"strings"
)

type Template struct {
	PK            string             `dynamodbav:"PK"`
	SK            string             `dynamodbav:"SK"`
	Name          string             `dynamodbav:"name"`
	OrderInParent int                `dynamodbav:"order"`
	Exercises     []TemplateExercise `dynamodbav:"exercises"`
}

func (t *Template) UserID() string {
	return strings.TrimPrefix(t.PK, "USER#")
}

func (t *Template) ID() string {
	return strings.TrimPrefix(t.SK, "TEMPLATE#")
}

type TemplateExercise struct {
	ID            string `dynamodbav:"id" json:"id" example:"2025-07-18T05:40:48.329406Z"`
	ExerciseID    string `dynamodbav:"exercise" json:"exercise"`
	ExerciseOrder int    `dynamodbav:"order" json:"order"`
	Sets          []Set  `dynamodbav:"sets" json:"sets"`
} // @name TemplateExercise

type TemplateIn struct {
	ID        string             `json:"id"`
	Name      string             `json:"name"`
	Order     int                `json:"order"`
	Exercises []TemplateExercise `json:"exercises"`
} // @name TemplateIn

func NewTemplate(t *TemplateIn, userId string) Template {
	return Template{
		PK:            fmt.Sprintf("%s%s", UserKey, userId),
		SK:            fmt.Sprintf("%s%s", TemplateKey, t.ID),
		Name:          t.Name,
		OrderInParent: t.Order,
		Exercises:     t.Exercises,
	}
}

type TemplateOut struct {
	ID        string             `json:"id" example:"2"`
	Name      string             `json:"name" example:"Legs & Shoulders"`
	Order     int                `json:"order" example:"1"`
	Exercises []TemplateExercise `json:"exercises"`
} // @name Template

func NewTemplateOut(t *Template) TemplateOut {
	return TemplateOut{
		ID:        t.ID(),
		Name:      t.Name,
		Order:     t.OrderInParent,
		Exercises: t.Exercises,
	}
}

type TemplateResponse struct {
	Templates []TemplateOut `json:"templates"`
}

func NewTemplateArray(templates []Template) []TemplateOut {
	out := make([]TemplateOut, len(templates))
	for i, t := range templates {
		out[i] = NewTemplateOut(&t)
	}
	return out
}
