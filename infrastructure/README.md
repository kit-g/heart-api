# Heart of Yours Infrastructure

This directory contains AWS CloudFormation templates and configuration files for deploying the Heart of Yours application infrastructure.

## Overview

The infrastructure is defined using AWS CloudFormation templates and is deployed using the AWS Serverless Application Model (SAM) CLI. The infrastructure is divided into two main components:

1. **API Infrastructure** - Contains resources for the Heart of Yours API, including Lambda functions, DynamoDB tables, API Gateway, and other supporting resources.
2. **CI/CD Infrastructure** - Contains resources for continuous integration and deployment, including IAM roles for GitHub Actions.

## Directory Structure

```
infrastructure/
├── api/
│   ├── api.toml - SAM CLI configuration for API deployment
│   └── api.yaml - CloudFormation template for API resources
├── ci/
│   ├── ci.toml - SAM CLI configuration for CI/CD deployment
│   └── ci.yaml - CloudFormation template for CI/CD resources
└── README.md - This file
```

## API Infrastructure (api.yaml)

The API infrastructure includes the following resources:

- **DynamoDB Table** - Stores workout data with TTL for scheduled deletions
- **API Gateway** - REST API for the Heart of Yours application
- **EventBridge Scheduler Group** - For scheduling account deletion jobs
- **SNS Topic** - For monitoring notifications
- **IAM Role** - For Lambda execution with permissions for various AWS services
- **Lambda Functions**:
  - **ApiFunction** - Handles API requests
  - **BackgroundFunction** - Processes background jobs
- **CloudWatch Log Group** - For API function logs

### Parameters

The API infrastructure template accepts the following parameters:

- `DbHost` - Postgres database endpoint
- `DbPassword` - Postgres database password
- `DbUser` - Postgres database user
- `Env` - Environment (dev or prod)
- `FirebaseCredentials` - Firebase JSON key
- `WorkoutsDatabaseName` - Name of the DynamoDB table for workouts (default: "workouts")

### Environment-Specific Settings

The template includes mappings for environment-specific settings:

- **Dev Environment**:
  - Account deletion offset: 2 days
  - CORS origins: dev domains and localhost
  - Log retention: 3 days
  - S3 buckets: dev buckets
  - Database deletion protection: disabled

- **Prod Environment**:
  - Account deletion offset: 30 days
  - CORS origins: production domains
  - Log retention: 90 days
  - Database deletion protection: enabled

## CI/CD Infrastructure (ci.yaml)

The CI/CD infrastructure includes the following resources:

- **IAM Role** - For GitHub Actions with permissions to:
  - Deploy to S3 (put, list, delete objects)
  - Create CloudFront invalidations
  - Update Lambda function code

### Parameters

The CI/CD infrastructure template accepts the following parameters:

- `Env` - Environment (dev or prod)

### Environment-Specific Settings

The template includes mappings for environment-specific settings:

- **Dev Environment**:
  - CloudFront distribution ID
  - GitHub identity provider ARN
  - S3 hosting bucket

- **Prod Environment**:
  - (Values to be filled in for production)

## Deployment

### Prerequisites

- AWS CLI installed and configured
- AWS SAM CLI installed
- Appropriate AWS credentials with permissions to create the resources

### Deploying the API Infrastructure

1. Navigate to the `infrastructure/api` directory:
   ```bash
   cd infrastructure/api
   ```

2. Deploy using the SAM CLI:
   ```bash
   sam deploy --config-file api.toml --config-env dev
   ```

   This will:
   - Create a CloudFormation stack named "heart-api"
   - Upload deployment artifacts to the specified S3 bucket
   - Deploy the resources defined in api.yaml with the parameters specified in api.toml

### Deploying the CI/CD Infrastructure

1. Navigate to the `infrastructure/ci` directory:
   ```bash
   cd infrastructure/ci
   ```

2. Deploy using the SAM CLI:
   ```bash
   sam deploy --config-file ci.toml --config-env dev
   ```

   This will:
   - Create a CloudFormation stack named "heart-ci"
   - Upload deployment artifacts to the specified S3 bucket
   - Deploy the resources defined in ci.yaml with the parameters specified in ci.toml

## Security Considerations

- Sensitive parameters like database credentials and Firebase credentials are marked with `NoEcho: true` to prevent them from being displayed in the CloudFormation console or API responses.
- IAM roles follow the principle of least privilege, granting only the permissions necessary for the application to function.
- Database deletion protection is enabled in the production environment to prevent accidental deletion.

## Maintenance

- To update the infrastructure, modify the CloudFormation templates and redeploy using the SAM CLI.
- To update the Lambda function code, use the GitHub Actions workflow defined in `.github/workflows/deploy.yaml`.
- To update environment-specific settings, modify the mappings in the CloudFormation templates.