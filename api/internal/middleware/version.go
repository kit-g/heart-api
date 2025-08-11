package middleware

import (
	"os"
	"strings"

	"github.com/Masterminds/semver/v3"
	"github.com/gin-gonic/gin"
)

const (
	code     = 426
	language = "Please update the app to continue."
)

func Version() gin.HandlerFunc {
	return func(c *gin.Context) {
		appVersion := c.GetHeader("X-App-Version")

		if appVersion == "" {
			c.AbortWithStatusJSON(code, gin.H{"message": language})
			return
		}

		currentVersion := strings.Split(appVersion, "+")[0]

		v, err := semver.NewVersion(currentVersion)

		if err != nil {
			c.AbortWithStatusJSON(code, gin.H{"message": language})
			return
		}

		minVersion, err := semver.NewVersion(os.Getenv("MIN_APP_VERSION"))
		if err != nil {
			c.Next()
			return
		}

		if v.LessThan(minVersion) {
			c.AbortWithStatusJSON(code, gin.H{
				"message":        language,
				"minVersion":     os.Getenv("MIN_APP_VERSION"),
				"currentVersion": currentVersion,
			})
			return
		}

		c.Next()
	}
}
