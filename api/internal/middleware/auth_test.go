package middleware

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"firebase.google.com/go/v4/auth"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
)

func newAuthTestRouter() *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.Use(Authentication())
	r.GET("/me", func(c *gin.Context) {
		// read userID and echo it back
		uid, _ := c.Get("userID")
		c.JSON(200, gin.H{"userID": uid})
	})
	return r
}

func TestAuthentication_MissingHeader(t *testing.T) {
	r := newAuthTestRouter()
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/me", nil)
	r.ServeHTTP(rec, req)
	assert.Equal(t, http.StatusUnauthorized, rec.Code)
	assert.Contains(t, rec.Body.String(), "Missing or invalid token")
}

func TestAuthentication_InvalidBearerFormat(t *testing.T) {
	r := newAuthTestRouter()
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/me", nil)
	req.Header.Set("Authorization", "Token abc")
	r.ServeHTTP(rec, req)
	assert.Equal(t, http.StatusUnauthorized, rec.Code)
	assert.Contains(t, rec.Body.String(), "Missing or invalid token")
}

func TestAuthentication_VerifyFails_Unauthorized(t *testing.T) {
	// stub verify to return error
	orig := verifyIDToken
	verifyIDToken = func(ctx context.Context, idToken string) (*auth.Token, error) {
		return nil, assert.AnError
	}
	t.Cleanup(func() { verifyIDToken = orig })

	r := newAuthTestRouter()
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/me", nil)
	req.Header.Set("Authorization", "Bearer bad")
	r.ServeHTTP(rec, req)

	assert.Equal(t, http.StatusUnauthorized, rec.Code)
	assert.Contains(t, rec.Body.String(), "Invalid token")
}

func TestAuthentication_SetsUserID_OnSuccess(t *testing.T) {
	// stub verify to return a token with UID field
	orig := verifyIDToken
	verifyIDToken = func(ctx context.Context, idToken string) (*auth.Token, error) {
		return &auth.Token{UID: "user-123"}, nil
	}
	t.Cleanup(func() { verifyIDToken = orig })

	r := newAuthTestRouter()
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/me", nil)
	req.Header.Set("Authorization", "Bearer good")
	r.ServeHTTP(rec, req)

	assert.Equal(t, http.StatusOK, rec.Code)
	assert.Contains(t, rec.Body.String(), "user-123")
}
