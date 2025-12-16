package models

import (
	"slices"
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

func TestExtension(t *testing.T) {
	tests := []struct {
		name        string
		mimeType    string
		wantExt     string
		wantErr     bool
		errContains string
	}{
		{
			name:     "image/png returns .png",
			mimeType: "image/png",
			wantExt:  ".png",
			wantErr:  false,
		},
		{
			name:     "image/jpeg returns extension",
			mimeType: "image/jpeg",
			wantExt:  "", // order is OS-dependent; assert membership instead
			wantErr:  false,
		},
		{
			name:     "image/gif returns .gif",
			mimeType: "image/gif",
			wantExt:  ".gif",
			wantErr:  false,
		},
		{
			name:     "image/webp returns .webp",
			mimeType: "image/webp",
			wantExt:  ".webp",
			wantErr:  false,
		},
		{
			name:        "unknown mime type returns error",
			mimeType:    "image/unknown-format-xyz",
			wantErr:     true,
			errContains: "no Extension found for",
		},
		{
			name:        "empty string returns error",
			mimeType:    "",
			wantErr:     true,
			errContains: "mime: no media type",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := Extension(tt.mimeType)

			if tt.wantErr {
				assert.Error(t, err)
				if tt.errContains != "" {
					assert.Contains(t, err.Error(), tt.errContains)
				}
				return
			}

			assert.NoError(t, err)

			if tt.mimeType == "image/jpeg" {
				acceptable := []string{".jpg", ".jpeg", ".jpe"}
				assert.True(t, slices.Contains(acceptable, got), "got %q, expected one of %v", got, acceptable)
				return
			}

			assert.Equal(t, tt.wantExt, got)
		})
	}
}

func TestExtension_DefaultMimeType(t *testing.T) {
	// Verify that the default MIME type works correctly
	ext, err := Extension(DefaultMimeType)

	assert.NoError(t, err)
	assert.Equal(t, ".png", ext)
}
