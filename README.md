# Heart of Yours

A comprehensive fitness tracking application with a serverless backend architecture.

## Project Overview

Heart of Yours is a fitness tracking application that allows users to:
- Track workouts and exercise history
- Create and manage workout templates
- Manage a personal exercise library
- Monitor fitness progress

The application is built with a serverless architecture on AWS, featuring a Go-based API backend.

## Repository Structure

This repository contains the complete codebase for the Heart of Yours application:

```
heart-go/
├── api/                 # Go-based serverless API
├── infrastructure/      # AWS CloudFormation templates
├── scripts/             # Utility scripts
└── .github/workflows/   # CI/CD pipelines
```

### Key Components

#### API

The `api/` directory contains the Go-based serverless API that powers the Heart of Yours application. It handles user authentication, workout tracking, exercise management, and more.

[See API documentation →](api/README.md)

#### Infrastructure

The `infrastructure/` directory contains AWS CloudFormation templates and configuration files for deploying the application infrastructure, including Lambda functions, DynamoDB tables, API Gateway, and CI/CD resources.

[See Infrastructure documentation →](infrastructure/README.md)

#### Scripts

The `scripts/` directory contains utility scripts:
- `deploy.sh` - Helper script for deploying infrastructure using AWS SAM
- `docs.sh` - Script for generating API documentation using Swagger

#### CI/CD

The `.github/workflows/` directory contains GitHub Actions workflows for continuous integration and deployment:
- `deploy.yaml` - Workflow for building, testing, and deploying the API to AWS Lambda

## Getting Started

### Prerequisites

- Go 1.24 or higher
- AWS CLI configured with appropriate permissions
- AWS SAM CLI for infrastructure deployment
- Firebase project with authentication enabled

### Development Workflow

1. **API Development**:
   - Follow the instructions in the [API README](api/README.md) for local development and testing

2. **Infrastructure Deployment**:
   - Follow the instructions in the [Infrastructure README](infrastructure/README.md) for deploying the AWS resources

3. **CI/CD**:
   - Changes pushed to the `main` branch will automatically trigger the deployment workflow

## Architecture

Heart of Yours uses a serverless architecture on AWS:

- **Compute**: AWS Lambda functions for API and background processing
- **Storage**: 
  - DynamoDB for workout data
  - S3 for file storage
- **API Gateway**: REST API endpoints
- **Authentication**: Firebase Authentication
- **Scheduling**: EventBridge Scheduler for background tasks
- **Monitoring**: SNS for notifications and CloudWatch for logging

