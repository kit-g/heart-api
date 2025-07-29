package models

import (
	"time"
)

type User struct {
	Username                string     `json:"displayName" example:"jane_doe" binding:"required"`
	Email                   string     `json:"email" example:"jane_doe@mail.com"`
	FirebaseUID             string     `json:"id" example:"HW4beTVvbTUPRxun9MXZxwKPjmC2" binding:"required"`
	AvatarUrl               *string    `json:"avatar" example:"https://example.com/avatar.png"`
	AccountDeletionSchedule *string    `json:"accountDeletionSchedule,omitempty" example:"arn:aws:scheduler:ca-central-1:123:schedule/account-deletions/account-deletion-123"`
	ScheduledForDeletionAt  *time.Time `json:"scheduledForDeletionAt,omitempty" example:"2022-01-01T00:00:00.000Z"`
} // @name User

type UserInternal struct {
	PK                      string     `dynamodbav:"PK"`
	SK                      string     `dynamodbav:"SK"`
	Username                string     `dynamodbav:"username"`
	Email                   string     `dynamodbav:"email"`
	FirebaseUID             string     `dynamodbav:"firebase_uid"`
	AvatarUrl               *string    `dynamodbav:"avatar"`
	AccountDeletionSchedule *string    `dynamodbav:"account_deletion_schedule"`
	ScheduledForDeletionAt  *time.Time `dynamodbav:"scheduled_for_deletion_at"`
}

type UserPublic struct {
	Username    string  `json:"displayName" example:"jane_doe" binding:"required"`
	FirebaseUID string  `json:"id" example:"HW4beTVvbTUPRxun9MXZxwKPjmC2" binding:"required"`
	AvatarUrl   *string `json:"avatar" example:"https://example.com/avatar.png"`
}

func NewUserInternal(u *User) UserInternal {
	return UserInternal{
		PK:                      UserKey + u.FirebaseUID,
		SK:                      UserKey + u.FirebaseUID,
		Username:                u.Username,
		Email:                   u.Email,
		FirebaseUID:             u.FirebaseUID,
		AvatarUrl:               u.AvatarUrl,
		AccountDeletionSchedule: u.AccountDeletionSchedule,
		ScheduledForDeletionAt:  u.ScheduledForDeletionAt,
	}
}

func NewUser(u *UserInternal) User {
	return User{
		Username:                u.Username,
		Email:                   u.Email,
		FirebaseUID:             u.FirebaseUID,
		AvatarUrl:               u.AvatarUrl,
		AccountDeletionSchedule: u.AccountDeletionSchedule,
		ScheduledForDeletionAt:  u.ScheduledForDeletionAt,
	}
}

func NewUserOut(u *User) UserPublic {
	return UserPublic{
		Username:    u.Username,
		FirebaseUID: u.FirebaseUID,
		AvatarUrl:   u.AvatarUrl,
	}
}

type EditAccountRequest struct {
	Action   string  `json:"action" example:"removeAvatar" binding:"required"`
	MimeType *string `json:"mimeType,omitempty" example:"image/png"`
} // @name EditAccountRequest

type PresignedUrlResponse struct {
	URL    string            `json:"url"`
	Fields map[string]string `json:"fields"`
} // @name PresignedUrlResponse
