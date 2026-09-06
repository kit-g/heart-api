import 'package:heart/db/db.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/middleware/events.dart';
import 'package:heart/models/creates.dart';
import 'package:heart/models/exercise_preferences.dart';
import 'package:heart/models/exercises.dart';
import 'package:heart/models/images.dart';
import 'package:heart/models/profile.dart';
import 'package:heart/models/workouts.dart';
import 'package:heart/storage/s3.dart';
import 'package:heart_models/heart_models.dart' hide ExerciseService, WorkoutService, TemplateService;
import 'package:mockito/annotations.dart';

@GenerateMocks([
  AppConfig,
  Database,
  Storage,
  ApiProfileService,
  ApiImageDbService,
  ApiImageStorageService,
  ApiWorkoutService,
  IdempotentTemplateService,
  IdempotentTemplateFolderService,
  ExerciseService,
  ChartPreferenceService,
  ApiExercisePreferenceService,
  IdempotentGoalService,
  CommentService,
  ConnectionsService,
  DeviceService,
  EventPublisher,
])
void main() {}
