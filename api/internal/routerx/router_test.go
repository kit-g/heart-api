package routerx

import (
	"encoding/json"
	"heart/internal/config"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestRouter_Health(t *testing.T) {
	config.App = &config.AppConfig{SwaggerConfig: config.SwaggerConfig{DocsEnabled: false}}
	r := Router("")

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	r.ServeHTTP(rec, req)

	assert.Equal(t, http.StatusOK, rec.Code)
	var payload map[string]string
	require.NoError(t, json.Unmarshal(rec.Body.Bytes(), &payload))
	assert.Equal(t, "up", payload["status"])
}

func TestRouter_Version(t *testing.T) {
	config.App = &config.AppConfig{SwaggerConfig: config.SwaggerConfig{DocsEnabled: false}}
	r := Router("")

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/version", nil)
	r.ServeHTTP(rec, req)

	assert.Equal(t, http.StatusOK, rec.Code)
	var payload map[string]string
	require.NoError(t, json.Unmarshal(rec.Body.Bytes(), &payload))
	assert.NotEmpty(t, payload["commit"])
	assert.NotEmpty(t, payload["deployedAt"])
}

func TestRouter_SwaggerToggle(t *testing.T) {
	// Disabled: route should 404
	config.App = &config.AppConfig{SwaggerConfig: config.SwaggerConfig{DocsEnabled: false}}
	r := Router("")
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/swagger/index.html", nil)
	r.ServeHTTP(rec, req)
	assert.Equal(t, http.StatusNotFound, rec.Code, "swagger should be disabled")

	// Enabled: route should be handled (often 200)
	config.App = &config.AppConfig{SwaggerConfig: config.SwaggerConfig{DocsEnabled: true}}
	r2 := Router("")
	rec2 := httptest.NewRecorder()
	req2 := httptest.NewRequest(http.MethodGet, "/swagger/index.html", nil)
	r2.ServeHTTP(rec2, req2)
	if rec2.Code != http.StatusOK {
		// Some setups respond 301/302 to /swagger/index.html → accept redirect as success
		assert.True(t, rec2.Code == http.StatusMovedPermanently || rec2.Code == http.StatusFound, "unexpected status: %d", rec2.Code)
		return
	}
	assert.Equal(t, http.StatusOK, rec2.Code)
}
