/// Push-notification copy templates, keyed by `[locale][event_type][variant]`.
///
/// In-process for now ("develop with a local file" — but bundling a YAML in
/// the Dart-AOT zip is an infra change; treating this map as the file for
/// now). When we move to S3-loaded config, the shape of the loaded blob is
/// this map.
///
/// A topic's `title` is what the push says, and `name` and `description` are what
/// a settings screen says about it. `comment.created` has a title per target.
/// The only argument any of them takes is `{name}`.
///
/// Templates are gender-neutral by design — keep them in present tense /
/// nominal forms so we don't need per-gender branching across languages.
const Map<String, Map<String, Map<String, String>>> notificationTemplates = {
  'en': {
    'comment.created': {
      'name': 'New comments',
      'description': 'When someone comments on your workout',
      'workout': '{name}: new comment on your workout',
      'workout_exercise': '{name}: new comment on your exercise',
      'exercise_set': '{name}: new comment on your set',
      'workout_image': '{name}: new comment on your photo',
    },
    'coaching.message': {
      'title': '{name} messaged you',
      'name': 'Messages',
      'description': 'When someone you train with writes to you',
    },
    'coaching.workout_digest': {
      'title': 'Your clients trained today',
      'name': 'Your clients\' workouts',
      'description': 'Once a day, when your clients have trained',
    },
    'coaching.invitation_accepted': {
      'title': '{name} accepted your invitation',
      'name': 'Invitations accepted',
      'description': 'When someone accepts your invitation',
    },
  },
  'en_CA': {
    'comment.created': {
      'name': 'New comments',
      'description': 'When someone comments on your workout',
      'workout': '{name}: new comment on your workout',
      'workout_exercise': '{name}: new comment on your exercise',
      'exercise_set': '{name}: new comment on your set',
      'workout_image': '{name}: new comment on your photo',
    },
    'coaching.message': {
      'title': '{name} messaged you',
      'name': 'Messages',
      'description': 'When someone you train with writes to you',
    },
    'coaching.workout_digest': {
      'title': 'Your clients trained today',
      'name': 'Your clients\' workouts',
      'description': 'Once a day, when your clients have trained',
    },
    'coaching.invitation_accepted': {
      'title': '{name} accepted your invitation',
      'name': 'Invitations accepted',
      'description': 'When someone accepts your invitation',
    },
  },
  'ru': {
    'comment.created': {
      'name': 'Новые комментарии',
      'description': 'Когда кто-то комментирует вашу тренировку',
      'workout': '{name}: новый комментарий к вашей тренировке',
      'workout_exercise': '{name}: новый комментарий к вашему упражнению',
      'exercise_set': '{name}: новый комментарий к вашему подходу',
      'workout_image': '{name}: новый комментарий к вашему фото',
    },
    'coaching.message': {
      'title': '{name}: новое сообщение',
      'name': 'Сообщения',
      'description': 'Когда вам пишет тот, с кем вы тренируетесь',
    },
    'coaching.workout_digest': {
      'title': 'Ваши клиенты сегодня тренировались',
      'name': 'Тренировки ваших клиентов',
      'description': 'Раз в день, когда ваши клиенты тренировались',
    },
    'coaching.invitation_accepted': {
      'title': '{name}: приглашение принято',
      'name': 'Принятые приглашения',
      'description': 'Когда кто-то принимает ваше приглашение',
    },
  },
  // neutral international Spanish; es_ES reaches these via the renderer's
  // base-language fallback, same chain as the exercise library
  'es': {
    'comment.created': {
      'name': 'Comentarios nuevos',
      'description': 'Cuando alguien comenta tu entrenamiento',
      'workout': '{name}: nuevo comentario en tu entrenamiento',
      'workout_exercise': '{name}: nuevo comentario en tu ejercicio',
      'exercise_set': '{name}: nuevo comentario en tu serie',
      'workout_image': '{name}: nuevo comentario en tu foto',
    },
    'coaching.message': {
      'title': '{name} te ha escrito',
      'name': 'Mensajes',
      'description': 'Cuando te escribe alguien con quien entrenas',
    },
    'coaching.workout_digest': {
      'title': 'Tus clientes han entrenado hoy',
      'name': 'Entrenamientos de tus clientes',
      'description': 'Una vez al día, cuando tus clientes han entrenado',
    },
    'coaching.invitation_accepted': {
      'title': '{name} ha aceptado tu invitación',
      'name': 'Invitaciones aceptadas',
      'description': 'Cuando alguien acepta tu invitación',
    },
  },
  // neutral international French; fr_CA reaches these via the same fallback
  'fr': {
    'comment.created': {
      'name': 'Nouveaux commentaires',
      'description': 'Quand quelqu\'un commente votre entraînement',
      'workout': '{name} : nouveau commentaire sur votre entraînement',
      'workout_exercise': '{name} : nouveau commentaire sur votre exercice',
      'exercise_set': '{name} : nouveau commentaire sur votre série',
      'workout_image': '{name} : nouveau commentaire sur votre photo',
    },
    'coaching.message': {
      'title': '{name} vous a écrit',
      'name': 'Messages',
      'description': 'Quand une personne avec qui vous vous entraînez vous écrit',
    },
    'coaching.workout_digest': {
      'title': 'Vos clients se sont entraînés aujourd\'hui',
      'name': 'Entraînements de vos clients',
      'description': 'Une fois par jour, quand vos clients se sont entraînés',
    },
    'coaching.invitation_accepted': {
      'title': '{name} a accepté votre invitation',
      'name': 'Invitations acceptées',
      'description': 'Quand quelqu\'un accepte votre invitation',
    },
  },
};
