package handlers

import (
	"errors"
	"heart/internal/dbx"
	"heart/internal/models"

	"github.com/gin-gonic/gin"
)

// GetTemplates godoc
//
//	@Summary		Lists workout templates
//	@Description	Returns all workout templates for the authenticated user
//	@Tags			templates
//	@Accept			json
//	@Produce		json
//	@ID				getTemplates
//	@Param			X-App-Version	header		string	false	"Client app version"
//	@Success		200				{array}		Template
//	@Failure		401				{object}	ErrorResponse	"Unauthorized"
//	@Failure		500				{object}	ErrorResponse	"Server error"
//	@Router			/templates [get]
//	@Security		BearerAuth
func GetTemplates(c *gin.Context, userId string) (any, error) {
	templates, err := dbx.GetTemplates(c.Request.Context(), userId)

	if err != nil {
		return nil, models.NewServerError(err)
	}

	return models.TemplateResponse{
		Templates: models.NewTemplateArray(templates),
	}, nil
}

// GetTemplate godoc
//
//	@Summary		Get workout template
//	@Description	Returns a specific workout template by ID
//	@Tags			templates
//	@Accept			json
//	@Produce		json
//	@ID				getTemplate
//	@Param			X-App-Version	header		string	false	"Client app version"
//	@Param			id				path		string	true	"Template ID"
//	@Success		200				{object}	Template
//	@Failure		401				{object}	ErrorResponse	"Unauthorized"
//	@Failure		404				{object}	ErrorResponse	"Not Found"
//	@Failure		500				{object}	ErrorResponse	"Server error"
//	@Router			/templates/{id} [get]
//	@Security		BearerAuth
func GetTemplate(c *gin.Context, userId string) (any, error) {
	templateId := c.Param("templateId")

	template, err := dbx.GetTemplate(c.Request.Context(), userId, templateId)

	if err != nil {
		return nil, models.NewServerError(err)
	}

	if template == nil {
		return nil, models.NewNotFoundError("Template not found", errors.New("template not found"))
	}

	return models.NewTemplateOut(template), nil
}

// MakeTemplate godoc
//
//	@Summary		Creates a workout template
//	@Description	Validates, saves and returns a workout template
//	@Tags			templates
//	@Accept			json
//	@Produce		json
//	@ID				makeTemplate
//	@Param			X-App-Version	header		string		false	"Client app version"
//	@Param			input			body		TemplateIn	true	"Template request"
//	@Success		200				{object}	Template
//	@Failure		401				{object}	ErrorResponse	"Unauthorized"
//	@Failure		500				{object}	ErrorResponse	"Server error"
//	@Router			/templates [post]
//	@Security		BearerAuth
func MakeTemplate(c *gin.Context, userId string) (any, error) {
	var template models.TemplateIn
	if err := c.BindJSON(&template); err != nil {
		return nil, models.NewValidationError(err)
	}

	created := models.NewTemplate(&template, userId)

	saved, err := dbx.SaveTemplate(c.Request.Context(), created)
	if err != nil {
		return nil, err
	}

	return models.NewTemplateOut(saved), nil
}

// DeleteTemplate godoc
//
//	@Summary		Delete workout template
//	@Description	Deletes a specific workout template by ID
//	@Tags			templates
//	@Accept			json
//	@Produce		json
//	@ID				deleteTemplate
//	@Param			X-App-Version	header	string	false	"Client app version"
//	@Param			id				path	string	true	"Template ID"
//	@Success		204				"No Content"
//	@Failure		401				{object}	ErrorResponse	"Unauthorized"
//	@Failure		404				{object}	ErrorResponse	"Not Found"
//	@Failure		500				{object}	ErrorResponse	"Server error"
//	@Router			/templates/{id} [delete]
//	@Security		BearerAuth
func DeleteTemplate(c *gin.Context, userId string) (any, error) {
	templateId := c.Param("templateId")

	err := dbx.DeleteTemplate(c.Request.Context(), userId, templateId)

	if err != nil {
		return nil, models.NewServerError(err)
	}

	return models.NoContent, nil
}
