/// What a set's type and effort may hold, and how long an exercise's note may
/// run — one definition for every writer (the workout input, the CSV import),
/// matching the database's own CHECKs.
library;

/// The set types lifting apps share — an ordinary working set, a warm-up, a
/// drop set, a set to failure — by their API word, each with the one letter
/// `exercise_sets.set_type` stores. The database's `_set_type_name` is the
/// reverse, for reads.
const setTypeCodes = {'normal': 'n', 'warmup': 'w', 'drop': 'd', 'failure': 'f'};

/// RPE's scale: 1–10, rated in whole or half points.
bool isRpe(num value) => value >= 1 && value <= 10 && (value * 2) == (value * 2).roundToDouble();

/// The longest note an exercise keeps, counted in code points as the column
/// counts it — so an emoji is one character, not two.
const maxExerciseNoteLength = 500;
