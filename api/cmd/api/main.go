//	@title			Heart of Yours API
//	@version		1.0
//	@description	A simple fitness tracker API
//	@termsOfService	http://swagger.io/terms/

//	@contact.name	Kit
//	@contact.url	https://github.com/kit-g

//	@license.name	MIT
//	@license.url	https://opensource.org/licenses/MIT

// @host		localhost:8080
// @BasePath	/
package main

import (
	"context"
	_ "heart/docs"
	"heart/internal/awsx"
	"heart/internal/config"
	"heart/internal/firebasex"
	"heart/internal/routerx"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/awslabs/aws-lambda-go-api-proxy/gin"

	"log"
	"os"
)

func Init() {
	var err error
	config.App, err = config.NewAppConfig()

	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
		return
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

	mode := os.Getenv("MODE")

	if mode == "lambda" {
		// Route Gin router with the Lambda adapter
		log.Println("Running in Lambda mode...")
		lambda.Start(ginadapter.New(r).ProxyWithContext)
	} else {
		// Default: local dev mode
		log.Println("Running in local mode on :8080...")
		if err := r.Run(":8080"); err != nil {
			log.Fatal("Server failed to start:", err)
		}
	}
}
