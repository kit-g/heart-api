package handlers

import (
	"context"
	"heart/internal/models"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
)

func newGinContextWithBody(method, path, body string) *gin.Context {
	gin.SetMode(gin.TestMode)
	rec := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(rec)
	c.Request = httptest.NewRequest(method, path, strings.NewReader(body))
	c.Request.Header.Set("Content-Type", "application/json")
	return c
}

func TestGetTemplates_Success(t *testing.T) {
	orig := dbGetTemplates
	dbGetTemplates = func(ctx context.Context, userId string) ([]models.Template, error) {
		return []models.Template{{Name: "T1", PK: "USER#" + userId, SK: "TEMPLATE#tid"}}, nil
	}
	t.Cleanup(func() { dbGetTemplates = orig })

	c := newCtx()
	res, err := GetTemplates(c, "u1")
	assert.NoError(t, err)
	out, ok := res.(models.TemplateResponse)
	assert.True(t, ok)
	assert.Len(t, out.Templates, 1)
	assert.Equal(t, "T1", out.Templates[0].Name)
}

func TestGetTemplate_NotFound(t *testing.T) {
	orig := dbGetTemplate
	dbGetTemplate = func(ctx context.Context, userId, id string) (*models.Template, error) { return nil, nil }
	t.Cleanup(func() { dbGetTemplate = orig })

	c := newCtx()
	c.Params = gin.Params{{Key: "templateId", Value: "tid"}}
	res, err := GetTemplate(c, "u1")
	assert.Nil(t, res)
	var nf *models.NotFoundError
	assert.ErrorAs(t, err, &nf)
}

func TestMakeTemplate_ValidationError(t *testing.T) {
	c := newGinContextWithBody("POST", "/templates", "not json")
	res, err := MakeTemplate(c, "u1")
	assert.Nil(t, res)
	_, isHTTP := err.(models.HTTPError)
	assert.True(t, isHTTP)
}

func TestDeleteTemplate_Success(t *testing.T) {
	orig := dbDeleteTemplate
	dbDeleteTemplate = func(ctx context.Context, userId, id string) error { return nil }
	t.Cleanup(func() { dbDeleteTemplate = orig })

	c := newCtx()
	c.Params = gin.Params{{Key: "templateId", Value: "tid"}}
	res, err := DeleteTemplate(c, "u1")
	assert.NoError(t, err)
	assert.Equal(t, models.NoContent, res)
}

func TestMakeTemplate_Saves(t *testing.T) {
	orig := dbSaveTemplate
	dbSaveTemplate = func(ctx context.Context, in models.Template) (*models.Template, error) {
		return &in, nil
	}
	t.Cleanup(func() { dbSaveTemplate = orig })

	body := `{"name":"Plan A","rounds":[]}`
	c := newGinContextWithBody("POST", "/templates", body)
	res, err := MakeTemplate(c, "uX")
	assert.NoError(t, err)
	out, ok := res.(models.TemplateOut)
	assert.True(t, ok)
	assert.Equal(t, "Plan A", out.Name)
}
