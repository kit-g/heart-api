# Heart of Yours

A comprehensive fitness tracking application with a modern, serverless backend architecture.

## Project Overview

Heart of Yours is a fitness tracking platform designed to help users:
- **Track Workouts**: Log exercises, sets, and reps with historical tracking.
- **Manage Templates**: Create and reuse workout templates for consistent routines.
- **Exercise Library**: Access a categorized library of exercises (managed via YAML/S3).
- **Progress Monitoring**: Visualize fitness progress through charts and data.

The project features a dual-generation serverless backend architecture on AWS, transitioning from Go to Dart.

## Repository Structure

This repository contains the complete codebase for the Heart of Yours application backend and infrastructure:

```text
heart-go/
├── api/             # 1st Generation: Go-based serverless API
├── api_v2/          # 2nd Generation: Dart-based serverless API (Current)
├── infrastructure/  # AWS CloudFormation (SAM) templates
├── content/         # Exercise library and static content definitions
├── scripts/         # Utility scripts (Python, Bash) for maintenance
└── .github/         # CI/CD pipelines (GitHub Actions)
```

### Core Components

#### API v2 (Second Generation)
The `api_v2/` directory contains the modern Dart-based API built with the [relic](https://pub.dev/packages/relic) framework. This version is the current focus, providing high-performance endpoints for exercises and user preferences.
[See API v2 documentation →](api_v2/README.md)

#### API (First Generation)
The `api/` directory contains the original Go-based serverless API. It provides a wide range of services including workout tracking, templates, and account management using the Gin framework.
[See API documentation →](api/README.md)

#### Infrastructure
The `infrastructure/` directory manages the AWS resources via CloudFormation and SAM. It includes definitions for Lambda functions, DynamoDB tables, API Gateway, SNS, and EventBridge scheduling.
[See Infrastructure documentation →](infrastructure/README.md)

#### Content & Scripts
- `content/`: Contains the master `exercise_library.yml` and other localized content used to populate the API's exercise data.
- `scripts/`: Python and shell scripts for processing content, generating documentation, and managing locales.

## Architecture

Heart of Yours leverages a fully serverless architecture on AWS for scalability and cost-efficiency:

- **Compute**: AWS Lambda (Go and Dart runtimes).
- **Storage**: 
  - **DynamoDB**: Stores workout logs, templates, and user preferences.
  - **S3**: Hosts the exercise library data and user-uploaded media.
- **API Gateway**: RESTful endpoints for both Go and Dart APIs.
- **Authentication**: Firebase Authentication (OIDC) for secure user access.
- **DevOps**: GitHub Actions for automated testing and SAM-based deployments.
- **Scheduling**: EventBridge Scheduler for background tasks
- **Monitoring**: SNS for notifications and CloudWatch for logging

## Getting Started

### Prerequisites
- **Go 1.24+** (for API v1)
- **Dart 3.10+** (for API v2)
- **AWS CLI & SAM CLI** (for infrastructure)
- **Firebase Project** (for authentication)

### Development Workflow
1. **Explore the APIs**: Choose the relevant directory (`api/` or `api_v2/`) and follow its specific setup instructions.
2. **Deploy Infrastructure**: Use the SAM CLI from the `infrastructure/` directory to provision your environment.
3. **Manage Content**: Update `content/exercise_library.yml` and use `scripts/` to sync with S3.

