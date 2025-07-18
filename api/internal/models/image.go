package models

type ImageDescription struct {
	Link   *string `dynamodbav:"link" json:"link" example:"https://example.com/image.jpg"`
	Width  *int    `dynamodbav:"width" json:"width" example:"100"`
	Height *int    `dynamodbav:"height" json:"height" example:"100"`
} // @name ImageDescription
