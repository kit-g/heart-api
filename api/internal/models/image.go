package models

import (
	"fmt"
	"mime"
)

type ImageDescription struct {
	Link   *string `dynamodbav:"link" json:"link" example:"https://example.com/image.jpg" binding:"required"`
	Width  *int    `dynamodbav:"width" json:"width" example:"100"`
	Height *int    `dynamodbav:"height" json:"height" example:"100"`
} // @name ImageDescription

type HasMimeType struct {
	MimeType *string `json:"mimeType,omitempty" example:"image/png"`
} // @name HasMimeType

const DefaultMimeType = "image/png"

// Extension returns the first file Extension associated with the provided MIME type or an error if none is found.
func Extension(mimeType string) (string, error) {
	extensions, err := mime.ExtensionsByType(mimeType)
	if err != nil {
		return "", err
	}
	if len(extensions) == 0 {
		return "", fmt.Errorf("no Extension found for %s", mimeType)
	}
	return extensions[0], nil
}
