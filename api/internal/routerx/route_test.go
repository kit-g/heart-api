package routerx

import (
	"errors"
	"heart/internal/config"
	"heart/internal/models"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
)

func setupTestRouter() *gin.Engine {
	gin.SetMode(gin.TestMode)
	// Ensure config.App is non-nil for any code that reads it during routing setup
	if config.App == nil {
		config.App = &config.AppConfig{SwaggerConfig: config.SwaggerConfig{DocsEnabled: false}}
	}
	return gin.New()
}

func performRequest(r http.Handler, method, path string, headers map[string]string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, nil)
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)
	return rec
}

// Test Authenticated wrapper various paths
func TestAuthenticated_MissingUserID(t *testing.T) {
	r := setupTestRouter()
	r.GET("/t", Authenticated(func(c *gin.Context, userID string) (any, error) {
		return gin.H{"user": userID}, nil
	}))

	rec := performRequest(r, http.MethodGet, "/t", nil)
	assert.Equal(t, http.StatusUnauthorized, rec.Code)
}

func TestAuthenticated_WrongUserIDType(t *testing.T) {
	r := setupTestRouter()
	r.GET("/t", func(c *gin.Context) {
		c.Set("userID", 123) // wrong type
		Authenticated(func(c *gin.Context, userID string) (any, error) { return nil, nil })(c)
	})

	rec := performRequest(r, http.MethodGet, "/t", nil)
	assert.Equal(t, http.StatusInternalServerError, rec.Code)
}

func TestRunHandler_NoContent(t *testing.T) {
	r := setupTestRouter()
	r.GET("/t", func(c *gin.Context) {
		c.Set("userID", "u1")
		Authenticated(func(c *gin.Context, userID string) (any, error) {
			return models.NoContent, nil
		})(c)
	})

	rec := performRequest(r, http.MethodGet, "/t", nil)
	assert.Equal(t, http.StatusNoContent, rec.Code)
	assert.Empty(t, rec.Body.String(), "204 should have empty body")
}

func TestRunHandler_HTTPError(t *testing.T) {
	r := setupTestRouter()
	r.GET("/t", func(c *gin.Context) {
		c.Set("userID", "u1")
		h := func(c *gin.Context, userID string) (any, error) {
			return nil, models.NewForbiddenError("Action not allowed", errors.New("forbidden"))
		}
		Authenticated(h)(c)
	})

	rec := performRequest(r, http.MethodGet, "/t", nil)
	assert.Equal(t, http.StatusForbidden, rec.Code)
	assert.Equal(t, "application/json", rec.Header().Get("Content-Type"))
}

func TestRunHandler_GenericError(t *testing.T) {
	r := setupTestRouter()
	r.GET("/t", func(c *gin.Context) {
		c.Set("userID", "u1")
		Authenticated(func(c *gin.Context, userID string) (any, error) {
			return nil, errors.New("boom")
		})(c)
	})

	rec := performRequest(r, http.MethodGet, "/t", nil)
	assert.Equal(t, http.StatusInternalServerError, rec.Code)
}

func TestAllowedOrigins(t *testing.T) {
	cases := []struct {
		in   string
		want []string
	}{
		{"https://a.com, https://b.com,,  ,http://c.com ", []string{"https://a.com", "https://b.com", "http://c.com"}},
		{"", []string{}},
	}
	for _, tc := range cases {
		got := allowedOrigins(tc.in)
		assert.Equal(t, len(tc.want), len(got), "%q: wrong length", tc.in)
		for i := range got {
			assert.Equal(t, tc.want[i], got[i], "%q: element %d mismatch", tc.in, i)
		}
	}
}

func TestCORSMiddleware_AllowsKnownOrigin_AndOPTIONS(t *testing.T) {
	r := setupTestRouter()
	r.Use(CORSMiddleware("https://a.com,https://b.com"))
	r.GET("/ok", func(c *gin.Context) { c.String(200, "ok") })

	// Simple GET with allowed origin
	rec := performRequest(r, http.MethodGet, "/ok", map[string]string{"Origin": "https://a.com"})
	assert.Equal(t, 200, rec.Code)
	assert.Equal(t, "https://a.com", rec.Header().Get("Access-Control-Allow-Origin"))

	// OPTIONS should return 204 and set headers when origin allowed
	rec2 := performRequest(r, http.MethodOptions, "/ok", map[string]string{"Origin": "https://a.com"})
	assert.Equal(t, 204, rec2.Code)
	assert.Equal(t, "https://a.com", rec2.Header().Get("Access-Control-Allow-Origin"))
}

func TestCORSMiddleware_DisallowsUnknownOrigin(t *testing.T) {
	r := setupTestRouter()
	r.Use(CORSMiddleware("https://a.com"))
	r.GET("/ok", func(c *gin.Context) { c.String(200, "ok") })

	rec := performRequest(r, http.MethodGet, "/ok", map[string]string{"Origin": "https://evil.com"})
	assert.Equal(t, 200, rec.Code)
	assert.Empty(t, rec.Header().Get("Access-Control-Allow-Origin"))

	// OPTIONS from unknown origin should still be 204, without CORS headers
	rec2 := performRequest(r, http.MethodOptions, "/ok", map[string]string{"Origin": "https://evil.com"})
	assert.Equal(t, 204, rec2.Code)
	assert.Empty(t, rec2.Header().Get("Access-Control-Allow-Origin"))
}
