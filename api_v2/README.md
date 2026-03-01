# Heart of Yours API (v2)

The second generation of the Heart of Yours API, rewritten in Dart using the [relic](https://pub.dev/packages/relic) framework. This API serves as the backend for the Heart of Yours application, providing endpoints for exercise data, chart preferences, and version management.

## Features

- **Exercise Library**: Retrieve categorized exercise data stored in S3.
- **Chart Preferences**: Manage user-specific chart settings stored in DynamoDB.
- **Authentication**: Firebase-based authentication for secure data access.
- **Multi-region Support**: Configurable AWS region and environment settings.
- **Version Checking**: Integrated minimal app version validation.

## Tech Stack

- **Language**: [Dart 3.10+](https://dart.dev/)
- **Framework**: [relic](https://pub.dev/packages/relic)
- **Database**: AWS DynamoDB (for user data)
- **Storage**: AWS S3 (for content like exercise library)
- **Authentication**: Firebase / OpenID Connect

## Getting Started

### Prerequisites

- [Dart SDK](https://dart.dev/get-dart) (^3.10.4)
- AWS Credentials (configured via environment or profile)
- Firebase Project

### Environment Variables

The application requires the following environment variables to be set:

| Variable | Description | Required |
| --- | --- | --- |
| `REGION` | AWS Region (e.g., `us-east-1`) | Yes |
| `ENV` | Environment (`dev` or `prod`) | Yes |
| `FIREBASE_PROJECT_ID` | Your Firebase Project ID | Yes |
| `WORKOUTS_TABLE` | DynamoDB table name for workouts/preferences | Yes |
| `EXERCISE_BUCKET` | S3 bucket name for exercise content | Yes |
| `MIN_APP_VERSION` | Minimal supported application version (e.g., `1.0.0`) | Yes |
| `SHOULD_CHECK_VERSION` | Enable/Disable version check (`true`/`false`) | No |
| `LOG_LEVEL` | Logging level (default: `ALL`) | No |
| `AWS_PROFILE` | AWS profile name for credentials | No |
| `TEST_USER_ID` | Mock user ID for local testing | No |
| `SUPPORTED_LOCALES` | Comma-separated list of locales (default: `en`) | No |
| `DEFAULT_LOCALE` | Default locale for the API (default: `en`) | No |

### Running Locally

1. Install dependencies:
   ```bash
   dart pub get
   ```

2. Run the server:
   ```bash
   # Make sure to export required environment variables first
   dart run bin/main.dart
   ```

## API Endpoints

| Method | Endpoint | Description |
| --- | --- | --- |
| `GET` | `/version` | Get current API version information (Public) |
| `GET` | `/exercises` | Get list of exercises (Authenticated) |
| `GET` | `/charts` | Get user chart preferences (Authenticated) |
| `POST` | `/charts` | Save/Update a chart preference (Authenticated) |
| `DELETE` | `/charts/:id` | Delete a chart preference (Authenticated) |

## Project Structure

- `bin/`: Entry point of the application.
- `lib/core/`: Core request/response handling.
- `lib/db/`: Database interaction logic (DynamoDB).
- `lib/globals/`: Configuration, logging, and global utilities.
- `lib/middleware/`: Request interceptors for auth, config, and database injection.
- `lib/models/`: Data models and DTOs.
- `lib/routes/`: Route handlers for specific endpoints.
- `lib/storage/`: S3 storage interaction logic.

## Building for Production

The project includes a `Makefile` for building a Linux arm64 binary (e.g., for AWS Lambda):

```bash
make build-ApiV2Function ARTIFACTS_DIR=./build
```
