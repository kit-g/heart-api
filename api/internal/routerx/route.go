package routerx

import (
	"heart/internal/models"
	"net/http"

	"github.com/gin-gonic/gin"
)

type Handler func(c *gin.Context) (any, error)
type AuthHandler func(c *gin.Context, userID string) (any, error)

func Authenticated(handler AuthHandler) gin.HandlerFunc {
	return func(c *gin.Context) {
		raw, exists := c.Get("userID")
		if !exists {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "userID not found in context"})
			return
		}

		userID, ok := raw.(string)
		if !ok {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "userID has invalid type"})
			return
		}

		runHandler(c,
			func() (any, error) {
				return handler(c, userID)
			},
		)
	}
}

func runHandler(c *gin.Context, handler func() (any, error)) {
	result, err := handler()

	if result == models.NoContent {
		c.Status(http.StatusNoContent)
		return
	}

	if err != nil {
		switch e := err.(type) {
		case models.HTTPError:
			c.Data(e.Status(), "application/json", e.JSON())
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}

	c.JSON(http.StatusOK, result)
}
