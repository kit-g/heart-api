import 'dart:io';

import 'package:heart/models/imports.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

/// Rows copied byte for byte from real Hevy exports of one test account
/// (`test/fixtures/hevy/`, see heart-api#72): the Android app in English,
/// German and Korean, and hevy.com in English. The app writes CRLF rows,
/// escapes a line break inside a field as `\n` and translates catalog titles
/// and month names; the web writes LF rows with real line breaks and keeps
/// English. Every workout title says what it probes.
const _appEn =
    '"title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_lbs","reps","distance_km","duration_seconds","rpe"\r\n'
    '"P negative weight","3 Oct 2026, 10:00","3 Oct 2026, 10:10","","Bench Press (Barbell)",,"",0,"normal",-22.05,5,,,\r\n'
    '"Morning Lift","22 Sep 2026, 17:00","22 Sep 2026, 17:45","","Overhead Press (Barbell)",,"",0,"normal",93.7,8,,,\r\n'
    '"Morning Lift","22 Sep 2026, 06:00","22 Sep 2026, 06:50","exact title+start duplicate of the first Morning Lift","Overhead Press (Barbell)",,"",0,"normal",82.67,8,,,\r\n'
    '"Morning Lift","22 Sep 2026, 06:00","22 Sep 2026, 06:45","","Overhead Press (Barbell)",,"",0,"normal",88.18,8,,,\r\n'
    '"10 Degenerate sets","19 Sep 2026, 09:00","19 Sep 2026, 09:30","","Bench Press (Barbell)",,"",0,"normal",,0,,,\r\n'
    '"10 Degenerate sets","19 Sep 2026, 09:00","19 Sep 2026, 09:30","","Bench Press (Barbell)",,"",1,"normal",,10,,,\r\n'
    '"10 Degenerate sets","19 Sep 2026, 09:00","19 Sep 2026, 09:30","","Bench Press (Barbell)",,"",2,"normal",132.28,0,,,\r\n'
    '"10 Degenerate sets","19 Sep 2026, 09:00","19 Sep 2026, 09:30","","Bench Press (Barbell)",,"",3,"normal",1102.31,1,,,\r\n'
    '"10 Degenerate sets","19 Sep 2026, 09:00","19 Sep 2026, 09:30","","Bench Press (Barbell)",,"",4,"normal",2.76,999,,,\r\n'
    '"10 Degenerate sets","19 Sep 2026, 09:00","19 Sep 2026, 09:30","","Overhead Press (Barbell)",,"a set with nothing in it",0,"normal",,,,,\r\n'
    '"09 Same exercise twice (edited)","17 Sep 2026, 18:00","17 Sep 2026, 19:25","edited via PUT","Squat (Barbell)",,"first squat block, edited",0,"normal",220.46,5,,,\r\n'
    '"09 Same exercise twice (edited)","17 Sep 2026, 18:00","17 Sep 2026, 19:25","edited via PUT","Squat (Barbell)",,"first squat block, edited",1,"normal",225.97,3,,,\r\n'
    '"09 Same exercise twice (edited)","17 Sep 2026, 18:00","17 Sep 2026, 19:25","edited via PUT","Leg Press (Machine)",,"",0,"normal",396.83,10,,,\r\n'
    '"09 Same exercise twice (edited)","17 Sep 2026, 18:00","17 Sep 2026, 19:25","edited via PUT","Squat (Barbell)",,"back-off squat block",0,"normal",176.37,10,,,\r\n'
    '"07 Legs, ""Heavy"" & \'Wide\' — día 🦵","13 Sep 2026, 10:00","13 Sep 2026, 11:10","Multi-line description,\\nwith ""quotes"", commas, and emoji 🔥\\n\\nBlank line above. Кириллица. 日本語.","Squat (Barbell)",,"Line one, with a comma\\nLine two ""quoted""\\n\tTabbed line; semicolon\r\\nCRLF line 💪",0,"normal",220.46,5,,,\r\n'
    '"07 Legs, ""Heavy"" & \'Wide\' — día 🦵","13 Sep 2026, 10:00","13 Sep 2026, 11:10","Multi-line description,\\nwith ""quotes"", commas, and emoji 🔥\\n\\nBlank line above. Кириллица. 日本語.","Squat (Barbell)",,"Line one, with a comma\\nLine two ""quoted""\\n\tTabbed line; semicolon\r\\nCRLF line 💪",1,"normal",220.46,5,,,\r\n'
    '"07 Legs, ""Heavy"" & \'Wide\' — día 🦵","13 Sep 2026, 10:00","13 Sep 2026, 11:10","Multi-line description,\\nwith ""quotes"", commas, and emoji 🔥\\n\\nBlank line above. Кириллица. 日本語.","Leg Press (Machine)",,"",0,"normal",440.92,10,,,\r\n'
    '"05 Carries","9 Sep 2026, 17:00","9 Sep 2026, 17:40","","Farmers Walk",,"",0,"normal",70.55,,0.04,,\r\n'
    '"05 Carries","9 Sep 2026, 17:00","9 Sep 2026, 17:40","","Farmers Walk",,"",1,"normal",70.55,,0.04,38,\r\n'
    '"05 Carries","9 Sep 2026, 17:00","9 Sep 2026, 17:40","","Sled Pull",,"",0,"normal",220.46,,0.02,,\r\n'
    '"05 Carries","9 Sep 2026, 17:00","9 Sep 2026, 17:40","","Muffin Carry (Sandbag), ""heavy""",,"",0,"normal",99.21,,0.03,,\r\n'
    '"01 Push: set types + RPE","1 Sep 2026, 07:30","1 Sep 2026, 08:41","Set types: warmup, normal, failure, dropset. RPE incl. 7.5/8.5/9.5.","Bench Press (Barbell)",,"Paused first rep",0,"warmup",44.09,10,,,\r\n'
    '"01 Push: set types + RPE","1 Sep 2026, 07:30","1 Sep 2026, 08:41","Set types: warmup, normal, failure, dropset. RPE incl. 7.5/8.5/9.5.","Bench Press (Barbell)",,"Paused first rep",1,"warmup",88.18,8,,,\r\n'
    '"01 Push: set types + RPE","1 Sep 2026, 07:30","1 Sep 2026, 08:41","Set types: warmup, normal, failure, dropset. RPE incl. 7.5/8.5/9.5.","Bench Press (Barbell)",,"Paused first rep",2,"normal",132.28,5,,,7\r\n'
    '"01 Push: set types + RPE","1 Sep 2026, 07:30","1 Sep 2026, 08:41","Set types: warmup, normal, failure, dropset. RPE incl. 7.5/8.5/9.5.","Bench Press (Barbell)",,"Paused first rep",3,"normal",132.28,5,,,7.5\r\n'
    '"01 Push: set types + RPE","1 Sep 2026, 07:30","1 Sep 2026, 08:41","Set types: warmup, normal, failure, dropset. RPE incl. 7.5/8.5/9.5.","Bench Press (Barbell)",,"Paused first rep",4,"normal",137.79,5,,,8.5\r\n'
    '"01 Push: set types + RPE","1 Sep 2026, 07:30","1 Sep 2026, 08:41","Set types: warmup, normal, failure, dropset. RPE incl. 7.5/8.5/9.5.","Bench Press (Barbell)",,"Paused first rep",5,"failure",137.79,4,,,10\r\n'
    '"01 Push: set types + RPE","1 Sep 2026, 07:30","1 Sep 2026, 08:41","Set types: warmup, normal, failure, dropset. RPE incl. 7.5/8.5/9.5.","Incline Bench Press (Dumbbell)",,"",0,"normal",49.6,10,,,8\r\n'
    '"01 Push: set types + RPE","1 Sep 2026, 07:30","1 Sep 2026, 08:41","Set types: warmup, normal, failure, dropset. RPE incl. 7.5/8.5/9.5.","Incline Bench Press (Dumbbell)",,"",1,"normal",49.6,9,,,9\r\n'
    '"01 Push: set types + RPE","1 Sep 2026, 07:30","1 Sep 2026, 08:41","Set types: warmup, normal, failure, dropset. RPE incl. 7.5/8.5/9.5.","Incline Bench Press (Dumbbell)",,"",2,"normal",49.6,8,,,9.5\r\n'
    '"01 Push: set types + RPE","1 Sep 2026, 07:30","1 Sep 2026, 08:41","Set types: warmup, normal, failure, dropset. RPE incl. 7.5/8.5/9.5.","Triceps Rope Pushdown",,"",0,"normal",66.14,12,,,\r\n'
    '"01 Push: set types + RPE","1 Sep 2026, 07:30","1 Sep 2026, 08:41","Set types: warmup, normal, failure, dropset. RPE incl. 7.5/8.5/9.5.","Triceps Rope Pushdown",,"",1,"dropset",55.12,8,,,\r\n'
    '"01 Push: set types + RPE","1 Sep 2026, 07:30","1 Sep 2026, 08:41","Set types: warmup, normal, failure, dropset. RPE incl. 7.5/8.5/9.5.","Triceps Rope Pushdown",,"",2,"dropset",44.09,6,,,\r\n'
    '"01 Push: set types + RPE","1 Sep 2026, 07:30","1 Sep 2026, 08:41","Set types: warmup, normal, failure, dropset. RPE incl. 7.5/8.5/9.5.","Triceps Rope Pushdown",,"",3,"dropset",33.07,6,,,\r\n'
    '"A archived Stair Machine","20 Jan 2025, 12:00","20 Jan 2025, 12:30","","Stair Machine",,"",0,"normal",,,1,300,';

const _appDe =
    '"title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_lbs","reps","distance_km","duration_seconds","rpe"\r\n'
    '"01 Push: set types + RPE","1 Sept. 2026, 07:30","1 Sept. 2026, 08:41","Set types: warmup, normal, failure, dropset. RPE incl. 7.5/8.5/9.5.","Bankdrücken (Langhantel)",,"Paused first rep",0,"warmup",44.09,10,,,\r\n'
    '"01 Push: set types + RPE","1 Sept. 2026, 07:30","1 Sept. 2026, 08:41","Set types: warmup, normal, failure, dropset. RPE incl. 7.5/8.5/9.5.","Bankdrücken (Langhantel)",,"Paused first rep",1,"warmup",88.18,8,,,\r\n'
    '"01 Push: set types + RPE","1 Sept. 2026, 07:30","1 Sept. 2026, 08:41","Set types: warmup, normal, failure, dropset. RPE incl. 7.5/8.5/9.5.","Bankdrücken (Langhantel)",,"Paused first rep",2,"normal",132.28,5,,,7\r\n'
    '"01 Push: set types + RPE","1 Sept. 2026, 07:30","1 Sept. 2026, 08:41","Set types: warmup, normal, failure, dropset. RPE incl. 7.5/8.5/9.5.","Bankdrücken (Langhantel)",,"Paused first rep",3,"normal",132.28,5,,,7.5\r\n'
    '"01 Push: set types + RPE","1 Sept. 2026, 07:30","1 Sept. 2026, 08:41","Set types: warmup, normal, failure, dropset. RPE incl. 7.5/8.5/9.5.","Bankdrücken (Langhantel)",,"Paused first rep",4,"normal",137.79,5,,,8.5\r\n'
    '"01 Push: set types + RPE","1 Sept. 2026, 07:30","1 Sept. 2026, 08:41","Set types: warmup, normal, failure, dropset. RPE incl. 7.5/8.5/9.5.","Bankdrücken (Langhantel)",,"Paused first rep",5,"failure",137.79,4,,,10\r\n'
    '"01 Push: set types + RPE","1 Sept. 2026, 07:30","1 Sept. 2026, 08:41","Set types: warmup, normal, failure, dropset. RPE incl. 7.5/8.5/9.5.","Schrägbankdrücken (Kurzhantel)",,"",0,"normal",49.6,10,,,8\r\n'
    '"01 Push: set types + RPE","1 Sept. 2026, 07:30","1 Sept. 2026, 08:41","Set types: warmup, normal, failure, dropset. RPE incl. 7.5/8.5/9.5.","Schrägbankdrücken (Kurzhantel)",,"",1,"normal",49.6,9,,,9\r\n'
    '"01 Push: set types + RPE","1 Sept. 2026, 07:30","1 Sept. 2026, 08:41","Set types: warmup, normal, failure, dropset. RPE incl. 7.5/8.5/9.5.","Schrägbankdrücken (Kurzhantel)",,"",2,"normal",49.6,8,,,9.5\r\n'
    '"01 Push: set types + RPE","1 Sept. 2026, 07:30","1 Sept. 2026, 08:41","Set types: warmup, normal, failure, dropset. RPE incl. 7.5/8.5/9.5.","Trizeps-Pushdown mit Seil (Kabelzug)",,"",0,"normal",66.14,12,,,\r\n'
    '"01 Push: set types + RPE","1 Sept. 2026, 07:30","1 Sept. 2026, 08:41","Set types: warmup, normal, failure, dropset. RPE incl. 7.5/8.5/9.5.","Trizeps-Pushdown mit Seil (Kabelzug)",,"",1,"dropset",55.12,8,,,\r\n'
    '"01 Push: set types + RPE","1 Sept. 2026, 07:30","1 Sept. 2026, 08:41","Set types: warmup, normal, failure, dropset. RPE incl. 7.5/8.5/9.5.","Trizeps-Pushdown mit Seil (Kabelzug)",,"",2,"dropset",44.09,6,,,\r\n'
    '"01 Push: set types + RPE","1 Sept. 2026, 07:30","1 Sept. 2026, 08:41","Set types: warmup, normal, failure, dropset. RPE incl. 7.5/8.5/9.5.","Trizeps-Pushdown mit Seil (Kabelzug)",,"",3,"dropset",33.07,6,,,\r\n'
    '"M Jun: month coverage","16 Juni 2026, 18:00","16 Juni 2026, 18:45","","Squat (Langhantel)",,"",0,"normal",132.28,5,,,';

const _appKo =
    '"title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_lbs","reps","distance_km","duration_seconds","rpe"\r\n'
    '"03 Cardio mix","5 9월 2026, 06:10","5 9월 2026, 07:25","","달리기 (실외)",,"5k + a mile",0,"normal",,,5,1534,7\r\n'
    '"03 Cardio mix","5 9월 2026, 06:10","5 9월 2026, 07:25","","달리기 (실외)",,"5k + a mile",1,"normal",,,1.61,405,\r\n'
    '"03 Cardio mix","5 9월 2026, 06:10","5 9월 2026, 07:25","","트레드밀 (러닝머신)",,"",0,"normal",,,2,720,\r\n'
    '"03 Cardio mix","5 9월 2026, 06:10","5 9월 2026, 07:25","","트레드밀 (러닝머신)",,"",1,"normal",,,,600,\r\n'
    '"03 Cardio mix","5 9월 2026, 06:10","5 9월 2026, 07:25","","자전거 (실외)",,"",0,"normal",,,12.35,1800,\r\n'
    '"03 Cardio mix","5 9월 2026, 06:10","5 9월 2026, 07:25","","천국의 계단 (층수)",,"",0,"normal",,,,600,\r\n'
    '"03 Cardio mix","5 9월 2026, 06:10","5 9월 2026, 07:25","","천국의 계단 (계단 수)",,"",0,"normal",,,,300,\r\n'
    '"03 Cardio mix","5 9월 2026, 06:10","5 9월 2026, 07:25","","줄넘기",,"",0,"normal",,,,60,\r\n'
    '"03 Cardio mix","5 9월 2026, 06:10","5 9월 2026, 07:25","","줄넘기",,"",1,"normal",,,,90,\r\n'
    '"03 Cardio mix","5 9월 2026, 06:10","5 9월 2026, 07:25","","줄넘기",,"",2,"normal",,,,45,9\r\n'
    '"03 Cardio mix","5 9월 2026, 06:10","5 9월 2026, 07:25","","로잉 머신",,"",0,"normal",,,2,482,';

const _webEnUs =
    '"title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_lbs","reps","distance_km","duration_seconds","rpe"\n'
    '"15c US fall-back 2025","Nov 2, 2025, 1:30 AM","Nov 2, 2025, 1:45 AM","spans the repeated 01:00-02:00 hour","Squat (Barbell)",,"",0,"normal",209.44,5,,,\n'
    '"Morning Lift","Sep 22, 2026, 6:00 AM","Sep 22, 2026, 6:50 AM","exact title+start duplicate of the first Morning Lift","Overhead Press (Barbell)",,"",0,"normal",82.67,8,,,\n'
    '"Morning Lift","Sep 22, 2026, 5:00 PM","Sep 22, 2026, 5:45 PM","","Overhead Press (Barbell)",,"",0,"normal",93.7,8,,,\n'
    '"Morning Lift","Sep 22, 2026, 6:00 AM","Sep 22, 2026, 6:45 AM","","Overhead Press (Barbell)",,"",0,"normal",88.18,8,,,\n'
    '"07 Legs, ""Heavy"" & \'Wide\' — día 🦵","Sep 13, 2026, 10:00 AM","Sep 13, 2026, 11:10 AM","Multi-line description,\nwith ""quotes"", commas, and emoji 🔥\n\nBlank line above. Кириллица. 日本語.","Squat (Barbell)",,"Line one, with a comma\nLine two ""quoted""\n\tTabbed line; semicolon\r\nCRLF line 💪",0,"normal",220.46,5,,,\n'
    '"07 Legs, ""Heavy"" & \'Wide\' — día 🦵","Sep 13, 2026, 10:00 AM","Sep 13, 2026, 11:10 AM","Multi-line description,\nwith ""quotes"", commas, and emoji 🔥\n\nBlank line above. Кириллица. 日本語.","Squat (Barbell)",,"Line one, with a comma\nLine two ""quoted""\n\tTabbed line; semicolon\r\nCRLF line 💪",1,"normal",220.46,5,,,\n'
    '"07 Legs, ""Heavy"" & \'Wide\' — día 🦵","Sep 13, 2026, 10:00 AM","Sep 13, 2026, 11:10 AM","Multi-line description,\nwith ""quotes"", commas, and emoji 🔥\n\nBlank line above. Кириллица. 日本語.","Leg Press (Machine)",,"",0,"normal",440.92,10,,,\n'
    '"03 Cardio mix","Sep 5, 2026, 6:10 AM","Sep 5, 2026, 7:25 AM","","Running",,"5k + a mile",0,"normal",,,5,1534,7\n'
    '"03 Cardio mix","Sep 5, 2026, 6:10 AM","Sep 5, 2026, 7:25 AM","","Running",,"5k + a mile",1,"normal",,,1.61,405,\n'
    '"03 Cardio mix","Sep 5, 2026, 6:10 AM","Sep 5, 2026, 7:25 AM","","Treadmill",,"",0,"normal",,,2,720,\n'
    '"03 Cardio mix","Sep 5, 2026, 6:10 AM","Sep 5, 2026, 7:25 AM","","Treadmill",,"",1,"normal",,,,600,\n'
    '"03 Cardio mix","Sep 5, 2026, 6:10 AM","Sep 5, 2026, 7:25 AM","","Cycling",,"",0,"normal",,,12.35,1800,\n'
    '"03 Cardio mix","Sep 5, 2026, 6:10 AM","Sep 5, 2026, 7:25 AM","","Stair Machine (Floors)",,"",0,"normal",,,,600,\n'
    '"03 Cardio mix","Sep 5, 2026, 6:10 AM","Sep 5, 2026, 7:25 AM","","Stair Machine (Steps)",,"",0,"normal",,,,300,\n'
    '"03 Cardio mix","Sep 5, 2026, 6:10 AM","Sep 5, 2026, 7:25 AM","","Jump Rope",,"",0,"normal",,,,60,\n'
    '"03 Cardio mix","Sep 5, 2026, 6:10 AM","Sep 5, 2026, 7:25 AM","","Jump Rope",,"",1,"normal",,,,90,\n'
    '"03 Cardio mix","Sep 5, 2026, 6:10 AM","Sep 5, 2026, 7:25 AM","","Jump Rope",,"",2,"normal",,,,45,9\n'
    '"03 Cardio mix","Sep 5, 2026, 6:10 AM","Sep 5, 2026, 7:25 AM","","Rowing Machine",,"",0,"normal",,,2,482,';

/// The header of the en-US web file with the other unit pair, which the test
/// account never exported in: the only lines here not copied from a file.
const _kgMiles =
    '"title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_kg","reps","distance_miles","duration_seconds","rpe"\n'
    '"05 Carries","Sep 9, 2026, 5:00 PM","Sep 9, 2026, 5:40 PM","","Farmers Walk",,"",0,"normal",32,,0.02,,\n';

/// A real web row with its date as hevy.com writes it in German
/// (`Intl.DateTimeFormat('de', {dateStyle: 'medium', timeStyle: 'short'})`):
/// the one web format verified on a real German export, which isn't in the
/// fixtures.
const _webDe =
    '"title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_lbs","reps","distance_km","duration_seconds","rpe"\n'
    '"Morning Lift","22.09.2026, 17:00","22.09.2026, 17:45","","Overhead Press (Barbell)",,"",0,"normal",93.7,8,,,\n';

void main() {
  group('WorkoutImport.fromHevyCsv', () {
    final en = WorkoutImport.fromHevyCsv(_appEn);
    ImportedWorkout workout(WorkoutImport batch, String name) => batch.workouts.singleWhere((w) => w.name == name);

    test('reports the source and groups the file into its contiguous workouts, in file order', () {
      expect(en.source, 'hevy');
      expect(en.workouts.map((w) => w.name), [
        'Morning Lift',
        'Morning Lift',
        'Morning Lift',
        '10 Degenerate sets',
        '09 Same exercise twice (edited)',
        "07 Legs, \"Heavy\" & 'Wide' — día 🦵",
        '05 Carries',
        '01 Push: set types + RPE',
        'A archived Stair Machine',
      ]);
      expect(en.workoutsDropped, 0);
      expect(en.setsDropped, 0);
    });

    test('reads app dates as naive local time, pinned by the utc offset', () {
      final push = workout(en, '01 Push: set types + RPE');
      expect(push.start, DateTime.utc(2026, 9, 1, 7, 30));
      expect(push.end, DateTime.utc(2026, 9, 1, 8, 41));

      final toronto = WorkoutImport.fromHevyCsv(_appEn, utcOffset: const Duration(hours: -4));
      expect(workout(toronto, '01 Push: set types + RPE').start, DateTime.utc(2026, 9, 1, 11, 30));
    });

    test('converts the header unit to kilograms and keeps kilometres and seconds', () {
      final bench = workout(en, '01 Push: set types + RPE').exercises.first.sets;
      expect(bench.first.weight, closeTo(20, 0.01));
      expect(bench.first.reps, 10);
      final carries = workout(en, '05 Carries').exercises.first.sets;
      expect(carries.first.weight, closeTo(32, 0.01));
      expect(carries.first.distance, 0.04);
      expect(carries.first.duration, isNull);
      expect(carries[1].duration, 38);
    });

    test('reads kg and miles headers too', () {
      final set = WorkoutImport.fromHevyCsv(_kgMiles).workouts.single.exercises.single.sets.single;
      expect(set.weight, 32);
      expect(set.distance, closeTo(0.0322, 0.0001));
    });

    test('keeps set types and RPE, including RPE on cardio', () {
      final push = workout(en, '01 Push: set types + RPE');
      final bench = push.exercises[0].sets;
      expect(bench.map((s) => s.type), ['warmup', 'warmup', null, null, null, 'failure']);
      expect(bench.map((s) => s.rpe), [null, null, 7, 7.5, 8.5, 10]);
      expect(push.exercises[2].sets.map((s) => s.type), [null, 'drop', 'drop', 'drop']);

      final web = WorkoutImport.fromHevyCsv(_webEnUs);
      final rope = workout(web, '03 Cardio mix').exercises.singleWhere((e) => e.name == 'Jump Rope');
      expect(rope.sets.last.rpe, 9);
      expect(rope.sets.last.duration, 45);
    });

    test('keeps the description as the workout note and the exercise note once', () {
      final push = workout(en, '01 Push: set types + RPE');
      expect(push.note, 'Set types: warmup, normal, failure, dropset. RPE incl. 7.5/8.5/9.5.');
      expect(push.exercises.first.note, 'Paused first rep');
      expect(push.exercises[1].note, isNull);
    });

    test('unescapes the app\'s line breaks so a note reads as the web writes it', () {
      final legs = workout(en, "07 Legs, \"Heavy\" & 'Wide' — día 🦵");
      expect(
        legs.note,
        'Multi-line description,\nwith "quotes", commas, and emoji 🔥\n\nBlank line above. Кириллица. 日本語.',
      );
      expect(
        legs.exercises.first.note,
        'Line one, with a comma\nLine two "quoted"\n\tTabbed line; semicolon\nCRLF line 💪',
      );

      final web = workout(WorkoutImport.fromHevyCsv(_webEnUs), "07 Legs, \"Heavy\" & 'Wide' — día 🦵");
      expect(web.toPayload(), legs.toPayload());
    });

    test('keeps an exercise logged twice as two exercises', () {
      final twice = workout(en, '09 Same exercise twice (edited)');
      expect(twice.exercises.map((e) => e.name), ['Squat (Barbell)', 'Leg Press (Machine)', 'Squat (Barbell)']);
      expect(twice.exercises.first.sets, hasLength(2));
      expect(twice.exercises.first.note, 'first squat block, edited');
      expect(twice.exercises.last.sets.single.reps, 10);
      expect(twice.exercises.last.note, 'back-off squat block');
    });

    test('skips and counts a negative measurement and a set with nothing in it', () {
      // the negative row was its workout's only row, so the workout is absent;
      // "0 reps" with a blank weight is an empty set too, since Hevy exports
      // zero as blank and a blank is null
      expect(en.rowsSkipped, 3);
      final degenerate = workout(en, '10 Degenerate sets');
      expect(degenerate.exercises.map((e) => e.name), ['Bench Press (Barbell)']);
      final sets = degenerate.exercises.single.sets;
      expect(sets.map((s) => s.reps), [10, null, 1, 999]);
      expect(sets.map((s) => s.weight), [isNull, closeTo(60, 0.01), closeTo(500, 0.01), closeTo(1.25, 0.01)]);
    });

    test('tells two workouts with the same title and start apart by their end', () {
      final lifts = en.workouts.where((w) => w.name == 'Morning Lift').toList();
      expect(lifts.map((w) => w.importId).toSet(), hasLength(3));
      expect(lifts.every((w) => w.importId.startsWith('hevy:')), isTrue);
    });

    test('tells two runs with the same title, start and end apart, deterministically', () {
      // the same real row twice, as two runs separated by another workout
      final rows = _appEn.split('\r\n');
      final sixFortyFive = rows[4];
      final csv = [rows[0], sixFortyFive, rows[2], sixFortyFive].join('\r\n');
      final ids = [for (final w in WorkoutImport.fromHevyCsv(csv).workouts) w.importId];
      expect(ids.toSet(), hasLength(3));
      expect([for (final w in WorkoutImport.fromHevyCsv(csv).workouts) w.importId], ids);
      final plain = en.workouts.singleWhere((w) => w.end == DateTime.utc(2026, 9, 22, 6, 45));
      expect(ids[0], plain.importId, reason: 'the first run keeps the plain identity');
    });

    test('keeps an archived catalog title, in English, as it is', () {
      final stairs = workout(en, 'A archived Stair Machine').exercises.single;
      expect(stairs.name, 'Stair Machine');
      expect(stairs.sets.single.distance, 1);
      expect(stairs.sets.single.duration, 300);
    });

    test('a German app export parses to the same batch as the English one', () {
      final de = WorkoutImport.fromHevyCsv(_appDe);
      expect(de.rowsSkipped, 0);
      expect(workout(de, '01 Push: set types + RPE').toPayload(), workout(en, '01 Push: set types + RPE').toPayload());
      final june = workout(de, 'M Jun: month coverage');
      expect(june.start, DateTime.utc(2026, 6, 16, 18));
      expect(june.exercises.single.name, 'Squat (Barbell)');
    });

    test('a Korean app export parses to the same batch as the English web export', () {
      final ko = WorkoutImport.fromHevyCsv(_appKo);
      final web = WorkoutImport.fromHevyCsv(_webEnUs);
      expect(ko.rowsSkipped, 0);
      expect(workout(ko, '03 Cardio mix').toPayload(), workout(web, '03 Cardio mix').toPayload());
      expect(workout(ko, '03 Cardio mix').exercises.map((e) => e.name), [
        'Running',
        'Treadmill',
        'Cycling',
        'Stair Machine (Floors)',
        'Stair Machine (Steps)',
        'Jump Rope',
        'Rowing Machine',
      ]);
    });

    test('reads the web export\'s English 12-hour dates and real line breaks', () {
      final web = WorkoutImport.fromHevyCsv(_webEnUs);
      expect(web.rowsSkipped, 0);
      final fallBack = workout(web, '15c US fall-back 2025');
      expect(fallBack.start, DateTime.utc(2025, 11, 2, 1, 30));
      expect(fallBack.end, DateTime.utc(2025, 11, 2, 1, 45));
      final evening = web.workouts.singleWhere((w) => w.start == DateTime.utc(2026, 9, 22, 17));
      expect(evening.end, DateTime.utc(2026, 9, 22, 17, 45));
    });

    test('a web export and an app export of the same history share import ids', () {
      final web = WorkoutImport.fromHevyCsv(_webEnUs);
      final webLifts = web.workouts.where((w) => w.name == 'Morning Lift').map((w) => w.importId).toSet();
      final appLifts = en.workouts.where((w) => w.name == 'Morning Lift').map((w) => w.importId).toSet();
      expect(webLifts, appLifts);
    });

    test('rejects a file whose dates it cannot read, naming the way out', () {
      expect(
        () => WorkoutImport.fromHevyCsv(_webDe),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('export from the Hevy app'))),
      );
    });

    test('rejects a file without the Hevy columns', () {
      expect(
        () => WorkoutImport.fromHevyCsv('Date,Workout Name,Exercise Name\n2023-01-15 17:35:12,Push,Bench\n'),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('expected Hevy columns'))),
      );
      expect(() => WorkoutImport.fromHevyCsv(''), throwsA(isA<FormatException>()));
    });

    test('lists every distinct exercise with a category guess and its set count', () {
      final names = en.exercises.map((e) => e['name']).toSet();
      expect(names, contains('Muffin Carry (Sandbag), "heavy"'));
      expect(en.exercises.singleWhere((e) => e['name'] == 'Sled Pull')['category'], 'Weighted Distance');
      expect(en.setsByExercise['Squat (Barbell)'], 5);
    });
  });

  group('WorkoutImport.fromHevyCsv on the whole exports', () {
    // the same 59-workout account exported by the Android app in three
    // languages, and the earlier 37-workout state of it by hevy.com
    const dir = 'test/fixtures/hevy';
    final app = {
      for (final lang in ['en', 'de', 'ko'])
        lang: WorkoutImport.fromHevyCsv(File('$dir/app-$lang.csv').readAsStringSync()),
    };
    final web = WorkoutImport.fromHevyCsv(File('$dir/web-en-US.csv').readAsStringSync());

    test('reads every row of the app files, CRLF and LF alike, bar the three degenerate ones', () {
      for (final MapEntry(key: lang, value: batch) in app.entries) {
        expect(batch.workouts, hasLength(58), reason: lang);
        expect(batch.rowsSkipped, 3, reason: lang);
        expect(batch.setsFound, 657, reason: lang);
      }
      expect(web.workouts, hasLength(36));
      expect(web.rowsSkipped, 3);
    });

    test('the three languages are one batch', () {
      final reference = [for (final w in app['en']!.workouts) w.toPayload()];
      expect([for (final w in app['de']!.workouts) w.toPayload()], reference);
      expect([for (final w in app['ko']!.workouts) w.toPayload()], reference);
    });

    test('the web export is the app export, workout for workout, bar the title renamed in between', () {
      final byId = {for (final w in app['en']!.workouts) w.importId: w};
      for (final w in web.workouts) {
        if (w.name?.startsWith('P LLLL') ?? false) continue;
        expect(byId[w.importId]?.toPayload(), w.toPayload(), reason: w.name);
      }
    });

    test('a window of zero length or ending before it starts is no window', () {
      final en = app['en']!;
      expect(en.workouts.singleWhere((w) => w.name == 'P date only').end, isNull);
      expect(en.workouts.singleWhere((w) => w.name == '16b Zero length').end, isNull);
      expect(en.workouts.singleWhere((w) => w.name == '16 Five hour session').end, DateTime.utc(2026, 9, 26, 13));
    });

    test('resolves every catalog title in every language to one English name', () {
      final english = app['en']!.setsByExercise.keys.toSet();
      expect(app['de']!.setsByExercise.keys.toSet(), english);
      expect(app['ko']!.setsByExercise.keys.toSet(), english);
      expect(english, hasLength(462));
      expect(
        english,
        containsAll(['Bench Press (Barbell)', 'Pistol Squat 🦵', 'Жим гантелей на наклонной (Dumbbell)']),
      );
    });
  });

  group('ImportSource', () {
    test('dispatches to the parser for the source', () {
      expect(ImportSource.hevy.parse(_appKo).source, 'hevy');
      expect(
        ImportSource.strong
            .parse('Date,Workout Name,Exercise Name,Weight,Reps\n2023-01-15 17:35:12,Push,Bench,80,5\n')
            .source,
        'strong',
      );
      expect(ImportSource.hevy.parse(_appKo, unit: MeasurementUnit.imperial).workouts, hasLength(1));
    });
  });
}
