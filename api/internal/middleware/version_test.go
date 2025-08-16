package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
)

// helper to build a gin.Engine with the version middleware and a simple handler
func newVersionTestRouter() *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.Use(Version())
	r.GET("/ok", func(c *gin.Context) { c.JSON(200, gin.H{"ok": true}) })
	return r
}

func TestVersion_MissingHeader(t *testing.T) {
	r := newVersionTestRouter()
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/ok", nil)
	r.ServeHTTP(rec, req)

	assert.Equal(t, 426, rec.Code)
	assert.Contains(t, rec.Body.String(), language)
}

func TestVersion_MalformedSemver(t *testing.T) {
	r := newVersionTestRouter()
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/ok", nil)
	req.Header.Set("X-App-Version", "bad.version")
	r.ServeHTTP(rec, req)

	assert.Equal(t, 426, rec.Code)
	assert.Contains(t, rec.Body.String(), language)
}

func TestVersion_MinVersionUnset_Allows(t *testing.T) {
	t.Setenv("MIN_APP_VERSION", "")
	r := newVersionTestRouter()
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/ok", nil)
	req.Header.Set("X-App-Version", "1.0.0")
	r.ServeHTTP(rec, req)
	assert.Equal(t, http.StatusOK, rec.Code)
}

func TestVersion_LowerThanMin_BlockedWithDetails(t *testing.T) {
	t.Setenv("MIN_APP_VERSION", "1.2.3")
	r := newVersionTestRouter()
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/ok", nil)
	req.Header.Set("X-App-Version", "1.2.2")
	r.ServeHTTP(rec, req)

	assert.Equal(t, 426, rec.Code)
	assert.Contains(t, rec.Body.String(), "\"minVersion\":\"1.2.3\"")
	assert.Contains(t, rec.Body.String(), "\"currentVersion\":\"1.2.2\"")
}

func TestVersion_EqualOrGreaterThanMin_Allows(t *testing.T) {
	t.Setenv("MIN_APP_VERSION", "1.2.3")
	r := newVersionTestRouter()
	// equal
	{
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodGet, "/ok", nil)
		req.Header.Set("X-App-Version", "1.2.3")
		r.ServeHTTP(rec, req)
		assert.Equal(t, http.StatusOK, rec.Code)
	}
	// greater
	{
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodGet, "/ok", nil)
		req.Header.Set("X-App-Version", "1.3.0")
		r.ServeHTTP(rec, req)
		assert.Equal(t, http.StatusOK, rec.Code)
	}
}

func TestVersion_WithBuildMetadata_AllowsWhenSatisfies(t *testing.T) {
	t.Setenv("MIN_APP_VERSION", "1.2.0")
	r := newVersionTestRouter()
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/ok", nil)
	req.Header.Set("X-App-Version", "1.2.3+45")
	r.ServeHTTP(rec, req)

	assert.Equal(t, http.StatusOK, rec.Code)
}
