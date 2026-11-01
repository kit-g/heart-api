import 'package:heart/core/mcp_router.dart';
import 'package:heart/core/oauth_router.dart';
import 'package:heart/core/response.dart';
import 'package:heart/routes/account.dart' as account;
import 'package:heart/routes/charts.dart' as charts;
import 'package:heart/routes/coach_library.dart' as coach_library;
import 'package:heart/routes/comments.dart' as comments;
import 'package:heart/routes/connections.dart' as connections;
import 'package:heart/routes/invitations.dart' as invitations;
import 'package:heart/routes/keys.dart' as keys;
import 'package:heart/routes/push.dart' as push;
import 'package:heart/routes/devices.dart' as devices;
import 'package:heart/routes/events.dart' as events;
import 'package:heart/routes/exercise_preferences.dart' as exercise_preferences;
import 'package:heart/routes/exercises.dart' as exercises;
import 'package:heart/routes/feedback.dart' as feedback;
import 'package:heart/routes/goals.dart' as goals;
import 'package:heart/routes/me_index.dart';
import 'package:heart/routes/images.dart' as images;
import 'package:heart/routes/misc.dart' as version;
import 'package:heart/routes/oauth.dart' as oauth;
import 'package:heart/routes/program_changes.dart' as changes;
import 'package:heart/routes/programs.dart' as programs;
import 'package:heart/routes/roster.dart' as roster;
import 'package:heart/routes/skips.dart' as skips;
import 'package:heart/routes/anomalies.dart' as anomalies;
import 'package:heart/routes/template_folders.dart' as folders;
import 'package:heart/routes/templates.dart' as templates;
import 'package:heart/routes/threads.dart' as threads;
import 'package:heart/routes/tokens.dart' as tokens;
import 'package:heart/routes/workouts.dart' as workouts;
import 'package:relic/relic.dart';

/// The app's own routes: Firebase-authenticated, version-gated, free to
/// change with the app.
final routes = <(String, Method), ModelHandler>{
  ('/accounts', .put): account.upsertAccount,
  ('/accounts/summary', .get): account.getAccountSummary,
  ('/accounts/connected-apps', .get): oauth.listConnectedApps,
  ('/accounts/connected-apps/:grantId', .delete): oauth.disconnectApp,
  ('/accounts/tokens', .get): tokens.listApiTokens,
  ('/accounts/tokens', .post): tokens.createApiToken,
  ('/accounts/tokens/:tokenId', .delete): tokens.revokeApiToken,
  ('/feedback', .post): feedback.submitFeedback,
  ('/accounts/:targetUserId/workouts', .get): workouts.getTargetUserWorkouts,
  ('/accounts/:targetUserId/programs', .get): changes.getCopies,
  ('/accounts/:targetUserId/programs/:programId', .get): changes.getCopy,
  ('/accounts/:targetUserId/programs/:programId', .put): changes.updateCopy,
  ('/accounts/:targetUserId/programs/:programId/changes', .get): changes.getCopyChanges,
  ('/accounts/:targetUserId/programs/:programId/changes/:changeId/revert', .post): changes.revertCopyChange,
  ('/accounts/:targetUserId/programs/:programId/sessions/:sessionId', .put): changes.updateCopySession,
  ('/accounts/:targetUserId/programs/:programId/sessions/:sessionId', .delete): changes.deleteCopySession,
  ('/accounts/:targetUserId/workouts/:workoutId/plan', .get): changes.getTargetWorkoutPlan,
  ('/accounts/:targetUserId/goals', .get): goals.getTargetUserGoals,
  ('/accounts/:targetUserId/skips', .get): skips.getTargetUserSkips,
  ('/accounts/:targetUserId/workouts/:workoutId', .get): workouts.getTargetUserWorkout,
  ('/accounts/:targetUserId/templates/:templateId', .post): templates.assignTemplateToUser,
  ('/accounts/:targetUserId/folders/:folderId', .post): folders.assignFolderToUser,
  ('/version', .get): version.getVersion,
  ('/charts', .get): charts.getChartPreferences,
  ('/charts', .post): charts.saveChartPreference,
  ('/charts/:preferenceId', .delete): charts.deleteChartPreference,
  ('/coach/clients', .get): roster.getRoster,
  ('/coach/clients/:connectionId/reviewed', .put): roster.markClientReviewed,
  ('/coach/feed', .get): roster.getCoachFeed,
  ('/comments', .get): comments.listComments,
  ('/comments', .post): comments.createComment,
  ('/comments/:commentId', .put): comments.editComment,
  ('/comments/:commentId', .delete): comments.deleteComment,
  ('/blocks', .get): invitations.getBlocks,
  ('/blocks/:blockedId', .delete): invitations.liftBlock,
  ('/connections', .get): connections.getConnections,
  ('/connections', .post): connections.createConnection,
  ('/connections/:connectionId', .delete): connections.deleteConnection,
  ('/connections/:connectionId', .put): connections.reactToConnection,
  ('/connections/:connectionId/shares', .put): connections.changeConnectionShares,
  ('/connections/:connectionId/thread', .post): threads.openThread,
  ('/devices', .post): devices.registerDevice,
  ('/invitations', .get): invitations.getInvitations,
  ('/invitations', .post): invitations.createInvitation,
  ('/invitations/:invitationId', .delete): invitations.cancelInvitation,
  ('/invitations/:invitationId/resend', .post): invitations.resendInvitation,
  ('/invitation-links/:token', .get): invitations.previewInvitation,
  ('/invitation-links/:token/accept', .post): invitations.acceptInvitation,
  ('/invitation-links/:token/decline', .post): invitations.declineInvitation,
  ('/invitation-links/:token/block', .post): invitations.blockInviter,
  ('/exercises', .get): exercises.getExercises,
  ('/exercises', .post): exercises.createExercise,
  ('/exercises/:exerciseId', .put): exercises.updateExercise,
  ('/exercises/:exerciseId/moves', .post): exercises.moveExerciseHistory,
  ('/exercise-preferences', .get): exercise_preferences.getExercisePreferences,
  ('/exercise-preferences', .post): exercise_preferences.saveExercisePreference,
  ('/exercise-preferences/:exerciseId', .delete): exercise_preferences.deleteExercisePreference,
  ('/goals', .post): goals.createGoal,
  ('/goals/:goalId', .put): goals.updateGoal,
  ('/goals/:goalId', .delete): goals.deleteGoal,
  ('/goals/:goalId/stages/:stageId', .put): goals.markStageAchieved,
  ('/programs', .get): programs.getMyPrograms,
  ('/programs', .post): programs.createProgram,
  ('/programs/:programId', .get): programs.getMyProgram,
  ('/programs/:programId', .put): programs.updateProgram,
  ('/programs/:programId', .delete): programs.deleteProgram,
  ('/programs/:programId/start', .post): coach_library.startProgram,
  ('/programs/:programId/changes', .get): changes.getProgramChanges,
  ('/programs/:programId/changes/:changeId/revert', .post): changes.revertProgramChange,
  ('/programs/:programId/actions', .get): programs.getProgramActions,
  ('/programs/:programId/actions', .post): programs.createProgramAction,
  ('/programs/:programId/actions/:actionId', .delete): programs.deleteProgramAction,
  ('/programs/:programId/bases', .get): programs.getProgramBases,
  ('/programs/:programId/bases', .post): programs.createProgramBase,
  ('/programs/:programId/bases/:baseId', .delete): programs.deleteProgramBase,
  ('/anomalies', .get): anomalies.getAnomalies,
  ('/anomalies/:anomalyId', .put): anomalies.resolveAnomaly,
  ('/keys/devices', .get): keys.getDevices,
  ('/keys/devices', .post): keys.publishDevice,
  ('/keys/devices/:deviceId', .delete): keys.removeDevice,
  ('/keys/devices/:deviceId/fallback', .put): keys.replaceFallbackKey,
  ('/keys/devices/:deviceId/one-time-keys', .get): keys.countOneTimeKeys,
  ('/keys/devices/:deviceId/one-time-keys', .post): keys.addOneTimeKeys,
  ('/keys/claims/:ownerId', .post): keys.claimKeys,
  ('/keys/queue', .get): keys.getQueue,
  ('/keys/queue', .post): keys.enqueue,
  ('/keys/queue/confirmations', .post): keys.confirmQueued,
  ('/library-programs', .get): coach_library.getCoachPrograms,
  ('/library-programs/:programId', .get): coach_library.getCoachProgram,
  ('/library-programs/:programId', .put): coach_library.saveCoachProgram,
  ('/library-programs/:programId', .delete): coach_library.deleteCoachProgram,
  ('/library-programs/:programId/holders', .get): coach_library.getCoachProgramHolders,
  ('/library-programs/:programId/send', .post): coach_library.sendCoachProgram,
  ('/library-programs/:programId/update', .post): changes.updateCopies,
  ('/notes', .get): threads.getNotes,
  ('/notes/:noteId', .put): threads.saveNote,
  ('/notes/:noteId', .delete): threads.deleteNote,
  ('/reports', .post): threads.fileReport,
  ('/threads', .get): threads.getThreads,
  ('/threads/:threadId/items', .get): threads.getThreadItems,
  ('/threads/:threadId/items', .post): threads.addThreadItem,
  ('/threads/:threadId/items', .delete): threads.clearThread,
  ('/threads/:threadId/read', .put): threads.markThreadRead,
  ('/push/settings', .get): push.getPushSettings,
  ('/push/settings/:topic', .put): push.setPushPreference,
  ('/push/settings/:topic', .delete): push.clearPushPreference,
  ('/skips', .get): skips.getMySkips,
  ('/skips', .post): skips.createSkip,
  ('/skips/:skipId', .delete): skips.deleteSkip,
  ('/events', .post): events.handler,
  ('/template-folders', .get): folders.getMyFolders,
  ('/template-folders', .post): folders.createFolder,
  ('/template-folders/:folderId', .put): folders.updateFolder,
  ('/template-folders/:folderId', .delete): folders.deleteFolder,
  ('/templates', .get): templates.getMyTemplates,
  ('/templates/:templateId', .get): templates.getMyTemplate,
  ('/templates', .post): templates.createTemplate,
  ('/templates/shares', .get): templates.getMyTemplateShares,
  ('/templates/:templateId', .put): templates.updateTemplate,
  ('/templates/:templateId', .delete): templates.deleteMyTemplate,
  ('/templates/shares/:shareId', .delete): templates.deleteMyTemplateShare,
  ('/workouts', .post): workouts.createWorkout,
  ('/workouts/imports', .post): workouts.importWorkouts,
  ('/workouts/images', .get): images.getGallery,
  ('/workouts/hidden', .get): workouts.getHiddenWorkouts,
  ('/workouts/:workoutId', .get): workouts.getWorkout,
  ('/workouts/:workoutId', .put): workouts.updateWorkout,
  ('/workouts/:workoutId', .patch): workouts.patchWorkout,
  ('/workouts/:workoutId', .delete): workouts.deleteWorkout,
  ('/workouts/:workoutId/plan', .put): changes.saveWorkoutPlan,
  ('/workouts/:workoutId/hidden', .put): workouts.hideWorkout,
  ('/workouts/:workoutId/hidden', .delete): workouts.unhideWorkout,
  ('/workouts/:workoutId/images', .put): images.presignWorkoutImage,
  ('/workouts/:workoutId/images', .delete): images.deleteWorkoutImage,
};

const _publicRoutes = {'/version', '/events'};

/// Reading a link is signed out, so someone without the app or an account can
/// see who is asking. Answering it isn't.
bool _isInvitationPreview(Request request) {
  final segments = request.url.pathSegments;
  return request.method == .get && segments.length == 2 && segments.first == 'invitation-links';
}

/// Whether [request] is for one of the app's own routes: those authenticate
/// with a Firebase ID token and carry the app version. Public routes need
/// neither, the `/me` and MCP surfaces authenticate with tokens, and the
/// authorization server's callers (clients, the consent page) have no app
/// version to send.
bool isAppRoute(Request request) {
  final path = request.url.path;
  if (_publicRoutes.contains(path)) return false;
  if (_isInvitationPreview(request)) return false;
  bool under(String prefix) => path == prefix || path.startsWith('$prefix/');
  return !under(tokenPrefix) && !under(mcpPrefix) && !under(oauthPrefix);
}
