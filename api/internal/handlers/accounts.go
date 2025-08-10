package handlers

import (
	"errors"
	"fmt"
	"heart/internal/awsx"
	"heart/internal/config"
	"heart/internal/dbx"
	"heart/internal/models"

	"github.com/gin-gonic/gin"
)

// GetAccount godoc
//
//	@Summary		Get user account
//	@Description	Returns user account information for the authenticated user
//	@Tags			accounts
//	@Accept			json
//	@Produce		json
//	@ID				getAccount
//	@Param			accountId	path		string	true	"Account ID"
//	@Success		200			{object}	User
//	@Failure		401			{object}	ErrorResponse	"Unauthorized"
//	@Failure		404			{object}	ErrorResponse	"Not Found"
//	@Failure		500			{object}	ErrorResponse	"Server error"
//	@Router			/accounts/{accountId} [get]
//	@Security		BearerAuth
func GetAccount(c *gin.Context, userId string) (any, error) {
	accountId := c.Param("accountId")

	user, err := dbx.GetAccount(c.Request.Context(), accountId)

	if err != nil {
		return nil, models.NewServerError(err)
	}

	if user == nil {
		return nil, models.NewNotFoundError("Account not found", errors.New("account not found"))
	}

	if userId == accountId {
		return user, nil
	}

	return models.NewUserOut(user), nil
}

// RegisterAccount godoc
//
//	@Summary		Creates an account record
//	@Description	Accounts are managed by Firebase so we just need to store them
//	@Tags			accounts
//	@Accept			json
//	@Produce		json
//	@ID				registerAccount
//	@Param			input	body		User	true	"User request"
//	@Success		201		{object}	User
//	@Failure		401		{object}	ErrorResponse	"Unauthorized"
//	@Failure		500		{object}	ErrorResponse	"Server error"
//	@Router			/accounts [post]
//	@Security		BearerAuth
func RegisterAccount(c *gin.Context, userId string) (any, error) {
	var user models.User
	if err := c.BindJSON(&user); err != nil {
		return nil, models.NewValidationError(err)
	}

	if user.FirebaseUID != userId {
		return nil, models.NewValidationError(fmt.Errorf("user id mismatch"))
	}

	account, err := dbx.SaveAccount(c.Request.Context(), userId, user)
	if err != nil {
		return nil, err
	}

	return account, nil
}

// EditAccount godoc
//
//	@Summary		Edit user account
//	@Description	Performs various account editing actions: undoAccountDeletion, removeAvatar, uploadAvatar
//	@Tags			accounts
//	@Accept			json
//	@Produce		json
//	@ID				editAccount
//	@Param			accountId	path		string				true	"Account ID"
//	@Param			input		body		EditAccountRequest	true	"Edit account request"
//	@Success		200			{object}	PresignedUrlResponse
//	@Success		204			"No Content"
//	@Failure		400			{object}	ErrorResponse	"Validation error"
//	@Failure		401			{object}	ErrorResponse	"Unauthorized"
//	@Failure		403			{object}	ErrorResponse	"Forbidden"
//	@Failure		500			{object}	ErrorResponse	"Server error"
//	@Router			/accounts/{accountId} [put]
//	@Security		BearerAuth
func EditAccount(c *gin.Context, userId string) (any, error) {
	var request models.EditAccountRequest
	if err := c.BindJSON(&request); err != nil {
		return nil, models.NewValidationError(err)
	}

	switch request.Action {
	case "undoAccountDeletion":
		user, err := dbx.GetAccount(c.Request.Context(), userId)

		if err != nil {
			return nil, models.NewServerError(err)
		}

		if user == nil {
			return nil, models.NewNotFoundError("Account not found", errors.New("account not found"))
		}

		if user.AccountDeletionSchedule != nil {
			err := awsx.DeleteAccountDeletionSchedule(c.Request.Context(), user.AccountDeletionSchedule)

			if err != nil {
				return nil, models.NewServerError(err)
			}
		}

		err = dbx.UndoAccountDeletion(c.Request.Context(), userId)

		if err != nil {
			return nil, models.NewServerError(err)
		}

		return models.NoContent, nil

	case "removeAvatar":
		_, err := awsx.DeleteObject(
			c.Request.Context(),
			config.App.MediaBucket,
			config.App.AvatarKey(userId),
		)

		if err != nil {
			return nil, models.NewServerError(err)
		}

		err = dbx.RemoveAvatar(c.Request.Context(), userId)

		if err != nil {
			return nil, models.NewServerError(err)
		}

		return models.NoContent, nil

	case "uploadAvatar":
		var mimeType string
		if request.MimeType == nil || *request.MimeType == "" {
			mimeType = defaultMimeType
		} else {
			mimeType = *request.MimeType
		}

		tag := config.App.UploadDestinationTag()

		response, err := awsx.GeneratePresignedPostURL(
			c.Request.Context(),
			config.App.UploadBucket,
			config.App.AvatarKey(userId),
			mimeType,
			&tag,
		)

		if err != nil {
			return nil, models.NewServerError(err)
		}

		return models.PresignedUrlResponse{
			URL:    response.URL,
			Fields: response.Values,
		}, nil
	}

	return nil, models.NewForbiddenError("Action not allowed", errors.New("action not allowed"))
}

// DeleteAccount godoc
//
//	@Summary		Delete user account
//	@Description	Schedules account deletion for the authenticated user
//	@Tags			accounts
//	@Accept			json
//	@Produce		json
//	@ID				deleteAccount
//	@Success		204	"No Content"
//	@Failure		401	{object}	ErrorResponse	"Unauthorized"
//	@Failure		404	{object}	ErrorResponse	"Not Found"
//	@Failure		500	{object}	ErrorResponse	"Server error"
//	@Router			/accounts [delete]
//	@Security		BearerAuth
func DeleteAccount(c *gin.Context, userId string) (any, error) {
	when, schedule, err := awsx.CreateAccountDeletionSchedule(c.Request.Context(), userId)

	if err != nil {
		return nil, models.NewServerError(err)
	}

	if when != nil && schedule != nil {
		err := dbx.ScheduleAccountForDeletion(c.Request.Context(), userId, *schedule, when.Unix())
		if err != nil {
			return nil, err
		}
	}

	return models.NoContent, nil
}

const defaultMimeType = "image/png"
