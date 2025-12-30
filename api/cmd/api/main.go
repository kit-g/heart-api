//	@title			Heart of Yours API
//	@version		1.0
//	@description	A simple fitness tracker API
//	@termsOfService	http://swagger.io/terms/

//	@contact.name	Kit
//	@contact.url	https://github.com/kit-g

//	@license.name	MIT
//	@license.url	https://opensource.org/licenses/MIT

//	@host		localhost:8080
//	@BasePath	/

// @securityDefinitions.apikey	BearerAuth
// @in							header
// @name						Authorization
package main

import (
	"context"
	"heart/docs"
	"heart/internal/awsx"
	"heart/internal/config"
	"heart/internal/firebasex"
	"heart/internal/routerx"
	"strings"

	"log"
)

func Init() {
	var err error
	config.App, err = config.NewAppConfig()

	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
		return
	}

	if config.App.DocsEnabled {
		docs.SwaggerInfo.Host = config.App.Host
		docs.SwaggerInfo.BasePath = config.App.BasePath
		if !strings.HasPrefix(config.App.Host, "localhost") {
			docs.SwaggerInfo.Schemes = []string{"https"}
		}
	}

	if config.App.Credentials != "" {
		if err := firebasex.Init(config.App.Credentials); err != nil {
			log.Fatal("Failed to initialize Firebase client:", err)
		}
	}

	if err := awsx.Init(context.Background(), config.App.AwsConfig); err != nil {
		log.Fatal("Failed to initialize AWS clients:", err)
		return
	}
}

func main() {
	Init()

	r := routerx.Router(config.App.CORSOrigins)

	if err := r.Run(":8080"); err != nil {
		log.Fatal("Server failed to start:", err)
	}
}
