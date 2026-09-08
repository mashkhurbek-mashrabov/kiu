import '../data/settings_repository.dart';
import '../domain/app_settings.dart';
import '../domain/lesson.dart';
import 'lesson_widget_service.dart';
import 'reminder_reconciler.dart';
import 'schedule_fetcher.dart';

class SyncResult {
  const SyncResult({required this.status, this.lessonCount = 0});
  final ScheduleSyncStatus status;
  final int lessonCount;
}

class ScheduleSyncService {
  ScheduleSyncService({
    required ScheduleFetcher fetcher,
    required SettingsRepository repository,
    required ReminderReconciler reconciler,
    LessonWidgetGateway? lessonWidgets,
  }) : _fetcher = fetcher,
       _repository = repository,
       _reconciler = reconciler,
       _lessonWidgets = lessonWidgets;

  final ScheduleFetcher _fetcher;
  final SettingsRepository _repository;
  final ReminderReconciler _reconciler;
  final LessonWidgetGateway? _lessonWidgets;

  Future<SyncResult> synchronize({String? userAgent}) async {
    await _repository.recordAttempt();
    if (userAgent != null && userAgent.isNotEmpty) {
      await _repository.saveWebViewUserAgent(userAgent);
    }
    try {
      final lessons = await _fetcher.fetch(
        userAgent: userAgent ?? _repository.webViewUserAgent,
      );
      final settings = _repository.loadSettings();
      await _reconciler.reconcile(lessons, settings);
      final syncedAt = DateTime.now();
      await _repository.recordSuccess(syncedAt);
      await _publishLessons(lessons, settings, syncedAt);
      return SyncResult(
        status: ScheduleSyncStatus.success,
        lessonCount: lessons.length,
      );
    } on ScheduleFetchException catch (error) {
      final status = error.code == 'auth'
          ? ScheduleSyncStatus.signInRequired
          : ScheduleSyncStatus.failed;
      await _repository.recordStatus(status.name);
      await _publishStatus(status);
      return SyncResult(status: status);
    } catch (_) {
      await _repository.recordStatus(ScheduleSyncStatus.failed.name);
      await _publishStatus(ScheduleSyncStatus.failed);
      return const SyncResult(status: ScheduleSyncStatus.failed);
    }
  }

  Future<void> _publishLessons(
    List<Lesson> lessons,
    AppSettings settings,
    DateTime lastSuccessfulSync,
  ) async {
    try {
      await _lessonWidgets?.publish(
        lessons,
        settings,
        lastSuccessfulSync: lastSuccessfulSync,
        showSuccessStatus: true,
      );
    } catch (_) {
      // Widget failure must not turn a successful LMS sync into a failed sync.
    }
  }

  Future<void> _publishStatus(ScheduleSyncStatus status) async {
    try {
      await _lessonWidgets?.publishStatus(status, _repository.loadSettings());
    } catch (_) {
      // Cached lessons and reminder reconciliation remain authoritative.
    }
  }
}
