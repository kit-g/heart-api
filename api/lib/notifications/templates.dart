/// Push-notification copy templates, keyed by `[locale][event_type][variant]`.
///
/// In-process for now ("develop with a local file" — but bundling a YAML in
/// the Dart-AOT zip is an infra change; treating this map as the file for
/// now). When we move to S3-loaded config, the shape of the loaded blob is
/// this map.
///
/// Templates are gender-neutral by design — keep them in present tense /
/// nominal forms so we don't need per-gender branching across languages.
const Map<String, Map<String, Map<String, String>>> notificationTemplates = {
  'en': {
    'comment.created': {
      'workout': '{author}: new comment on your workout',
      'workout_exercise': '{author}: new comment on your exercise',
      'exercise_set': '{author}: new comment on your set',
      'workout_image': '{author}: new comment on your photo',
    },
  },
  'en_CA': {
    'comment.created': {
      'workout': '{author}: new comment on your workout',
      'workout_exercise': '{author}: new comment on your exercise',
      'exercise_set': '{author}: new comment on your set',
      'workout_image': '{author}: new comment on your photo',
    },
  },
  'ru': {
    'comment.created': {
      'workout': '{author}: новый комментарий к вашей тренировке',
      'workout_exercise': '{author}: новый комментарий к вашему упражнению',
      'exercise_set': '{author}: новый комментарий к вашему подходу',
      'workout_image': '{author}: новый комментарий к вашему фото',
    },
  },
};
