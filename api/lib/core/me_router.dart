import 'package:heart/core/routing.dart';
import 'package:heart/db/db.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart/middleware/tokens.dart';
import 'package:heart/models/exports.dart';
import 'package:heart/routes/me_index.dart';
import 'package:relic/relic.dart';

/// The `/me` surface as a router of its own: a personal access token instead
/// of a Firebase session, its own rate limit and usage log, and only the
/// services its routes read. The app's router attaches it at [tokenPrefix].
RelicRouter buildMeRouter({required Database database, required ExportStorage storage}) {
  return RelicRouter()
    ..use('/', apiTokensDb(db: database))
    ..use('/', tokenAuthentication())
    ..use('/', profilesDb(db: database))
    ..use('/', workoutsDb(db: database))
    ..use('/', exercisesDb(db: database))
    ..use('/', templatesDb(db: database))
    ..use('/', templateFoldersDb(db: database))
    ..use('/', goalsDb(db: database))
    ..use('/', exportStorage(storage: storage))
    ..addRoutes(meRoutes);
}
