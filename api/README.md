# Heart of Yours API

A fitness tracking API built with Go, designed to run on AWS Lambda.

## Overview

Heart of Yours API is a serverless application that provides backend services for a fitness tracking application. It allows users to manage workouts, exercise templates, and track their fitness progress.

## Features

- User account management with Firebase authentication
- Exercise library management
- Workout tracking and history
- Workout template creation and management
- File uploads for user avatars
- API documentation with Swagger

## Technology Stack

- **Language**: Go 1.24+
- **Framework**: Gin web framework
- **Authentication**: Firebase Authentication
- **Cloud Services**:
  - AWS Lambda for compute
  - Amazon DynamoDB for data storage
  - Amazon S3 for file storage
  - AWS EventBridge Scheduler for scheduled tasks
  - Amazon SNS for notifications
- **Documentation**: Swagger/OpenAPI
- **Error Tracking**: Sentry (optional)

## Prerequisites

- Go 1.24 or higher
- AWS CLI configured with appropriate permissions
- Firebase project with authentication enabled

## Configuration

The application is configured using environment variables:

### Database Configuration
- `DB_HOST` - Database host (default: "localhost")
- `DB_PORT` - Database port (default: "5432")
- `DB_USER` - Database user
- `DB_PASSWORD` - Database password
- `DB_NAME` - Database name
- `DB_SSLMODE` - SSL mode for database connection (default: "disable")
- `APP_NAME` - Application name (default: "heart-api")

### AWS Configuration
- `REGION` - AWS region
- `WORKOUTS_TABLE` - DynamoDB table for workouts
- `UPLOAD_BUCKET` - S3 bucket for file uploads
- `MEDIA_BUCKET` - S3 bucket for media storage
- `SCHEDULE_GROUP` - EventBridge Scheduler group
- `BACKGROUND_FUNCTION` - ARN of the background processing Lambda function
- `BACKGROUND_ROLE` - IAM role for the background function
- `MONITORING_TOPIC` - SNS topic for monitoring
- `ACCOUNT_DELETION_OFFSET` - Days before account deletion (default: 30)

### Firebase Configuration
- `FIREBASE_CREDENTIALS` - Path to Firebase credentials JSON file

### Other Configuration
- `CORS_ORIGINS` - Comma-separated list of allowed origins for CORS (default: "*")
- `SENTRY_DSN` - Sentry DSN for error tracking (optional)

## Local Development

### Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/your-username/heart-go.git
   cd heart-go/api
   ```

2. Install dependencies:
   ```bash
   go mod download
   ```

3. Set up environment variables (create a `.env` file or export them directly)

4. Run the application locally:
   ```bash
   go run cmd/api/main.go
   ```

The API will be available at http://localhost:8080.

### Testing

Run the model tests:
```bash
cd internal/models
go test . -v
```

## Building for AWS Lambda

To build the Lambda function:

```bash
ARTIFACTS_DIR=. make build-ApiFunction
```

This will create a binary named `bootstrap` in the current directory.

To build the background processing function:

```bash
ARTIFACTS_DIR=. make build-BackgroundFunction
```

## Deployment

The application is deployed to AWS Lambda using GitHub Actions. The workflow is defined in `.github/workflows/deploy.yaml`.

To deploy manually:

1. Build the Lambda function:
   ```bash
   ARTIFACTS_DIR=. make build-ApiFunction
   ```

2. Zip the binary:
   ```bash
   zip function.zip bootstrap
   ```

3. Update the Lambda function code:
   ```bash
   aws lambda update-function-code \
     --function-name heart-api \
     --zip-file fileb://function.zip \
     --region ca-central-1
   ```

## API Documentation

The API is documented using Swagger. When running locally, you can access the Swagger UI at:

```
http://localhost:8080/swagger/index.html
```

## Project Structure

- `cmd/` - Application entry points
  - `api/` - API Lambda function
  - `background/` - Background processing Lambda function
- `docs/` - Swagger documentation
- `internal/` - Internal packages
  - `awsx/` - AWS service clients
  - `config/` - Configuration management
  - `dbx/` - Database access
  - `firebasex/` - Firebase client
  - `handlers/` - HTTP request handlers
  - `middleware/` - HTTP middleware
  - `models/` - Data models
  - `routerx/` - HTTP router setup

