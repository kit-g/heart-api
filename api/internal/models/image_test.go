package models

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestImageDescription(t *testing.T) {
	t.Run("ImageDescription with all fields", func(t *testing.T) {
		link := "https://example.com/image.jpg"
		width := 800
		height := 600

		img := ImageDescription{
			Link:   &link,
			Width:  &width,
			Height: &height,
		}

		assert.Equal(t, link, *img.Link)
		assert.Equal(t, width, *img.Width)
		assert.Equal(t, height, *img.Height)
	})

	t.Run("ImageDescription with nil fields", func(t *testing.T) {
		img := ImageDescription{}

		assert.Nil(t, img.Link)
		assert.Nil(t, img.Width)
		assert.Nil(t, img.Height)
	})
}
