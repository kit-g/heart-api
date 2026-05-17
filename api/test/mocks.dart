import 'package:heart/globals/config.dart';
import 'package:heart/models/exercises.dart';
import 'package:heart/models/images.dart';
import 'package:heart/models/profile.dart';
import 'package:heart/models/workouts.dart';
import 'package:heart_models/heart_models.dart' hide ExerciseService, WorkoutService, TemplateService;
import 'package:mockito/annotations.dart';

@GenerateMocks([
  AppConfig,
  ApiProfileService,
  ApiImageDbService,
  ApiImageStorageService,
  ApiWorkoutService,
  ApiTemplateService,
  ExerciseService,
  ChartPreferenceService,
  CommentService,
  ConnectionsService,
  DeviceService,
])
void main() {}
