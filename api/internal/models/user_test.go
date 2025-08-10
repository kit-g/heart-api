package models

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestUser_StructFields(t *testing.T) {
	user := User{
		user: user{
			Username:    strP("jane_doe"),
			Email:       "jane_doe@mail.com",
			FirebaseUID: "HW4beTVvbTUPRxun9MXZxwKPjmC2",
		},
		AccountDeletionSchedule: nil,
		ScheduledForDeletionAt:  nil,
	}

	assert.Equal(t, "jane_doe", *user.Username)
	assert.Equal(t, "jane_doe@mail.com", user.Email)
	assert.Equal(t, "HW4beTVvbTUPRxun9MXZxwKPjmC2", user.FirebaseUID)
	assert.Nil(t, user.AvatarUrl)
	assert.Nil(t, user.AccountDeletionSchedule)
	assert.Nil(t, user.ScheduledForDeletionAt)
}

func TestUser_WithOptionalFields(t *testing.T) {
	avatarUrl := "https://example.com/avatar.png"
	deletionSchedule := "2024-12-31"
	scheduledTime := time.Now()

	user := User{
		user: user{
			Username:    strP("jane_doe"),
			Email:       "jane_doe@mail.com",
			FirebaseUID: "HW4beTVvbTUPRxun9MXZxwKPjmC2",
			AvatarUrl:   &avatarUrl,
		},
		AccountDeletionSchedule: &deletionSchedule,
		ScheduledForDeletionAt:  &scheduledTime,
	}

	assert.Equal(t, "jane_doe", *user.Username)
	assert.Equal(t, "jane_doe@mail.com", user.Email)
	assert.Equal(t, "HW4beTVvbTUPRxun9MXZxwKPjmC2", user.FirebaseUID)
	assert.NotNil(t, user.AvatarUrl)
	assert.Equal(t, avatarUrl, *user.AvatarUrl)
	assert.NotNil(t, user.AccountDeletionSchedule)
	assert.Equal(t, deletionSchedule, *user.AccountDeletionSchedule)
	assert.NotNil(t, user.ScheduledForDeletionAt)
	assert.Equal(t, scheduledTime, *user.ScheduledForDeletionAt)
}

func TestEditAccountRequest_StructFields(t *testing.T) {
	tests := []struct {
		name    string
		request EditAccountRequest
	}{
		{
			name: "Request with action only",
			request: EditAccountRequest{
				Action: "removeAvatar",
			},
		},
		{
			name: "Request with action and mime type",
			request: EditAccountRequest{
				Action:   "uploadAvatar",
				MimeType: stringPtr("image/png"),
			},
		},
		{
			name: "Request with different action",
			request: EditAccountRequest{
				Action:   "updateProfile",
				MimeType: stringPtr("application/json"),
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.NotEmpty(t, tt.request.Action)
			if tt.request.MimeType != nil {
				assert.NotEmpty(t, *tt.request.MimeType)
			}
		})
	}
}

func TestEditAccountRequest_RequiredFields(t *testing.T) {
	request := EditAccountRequest{
		Action: "removeAvatar",
	}

	assert.Equal(t, "removeAvatar", request.Action)
	assert.Nil(t, request.MimeType)
}

func TestEditAccountRequest_WithMimeType(t *testing.T) {
	mimeType := "image/jpeg"
	request := EditAccountRequest{
		Action:   "uploadAvatar",
		MimeType: &mimeType,
	}

	assert.Equal(t, "uploadAvatar", request.Action)
	assert.NotNil(t, request.MimeType)
	assert.Equal(t, mimeType, *request.MimeType)
}

func TestPresignedUrlResponse_StructFields(t *testing.T) {
	fields := map[string]string{
		"key":       "uploads/avatar.png",
		"policy":    "eyJleHBpcmF0aW9uIjoi...",
		"signature": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
	}

	response := PresignedUrlResponse{
		URL:    "https://example.com/upload",
		Fields: fields,
	}

	assert.Equal(t, "https://example.com/upload", response.URL)
	assert.Equal(t, fields, response.Fields)
	assert.Len(t, response.Fields, 3)
}

func TestPresignedUrlResponse_EmptyFields(t *testing.T) {
	response := PresignedUrlResponse{
		URL:    "https://example.com/upload",
		Fields: make(map[string]string),
	}

	assert.Equal(t, "https://example.com/upload", response.URL)
	assert.NotNil(t, response.Fields)
	assert.Len(t, response.Fields, 0)
}

func TestUser_ZeroValues(t *testing.T) {
	var user User

	assert.Empty(t, user.Username)
	assert.Empty(t, user.Email)
	assert.Empty(t, user.FirebaseUID)
	assert.Nil(t, user.AvatarUrl)
	assert.Nil(t, user.AccountDeletionSchedule)
	assert.Nil(t, user.ScheduledForDeletionAt)
}

// Helper function to create string pointers
func stringPtr(s string) *string {
	return &s
}
