import 'package:flutter_test/flutter_test.dart';
import 'package:stms/models/violation.dart';
import 'package:stms/services/traffic_repository.dart';
import 'package:stms/services/traffic_store.dart';

ProcessingJob job(JobStatus status) => ProcessingJob(
  id: 'JOB-REFRESH',
  fileName: 'traffic.mp4',
  camera: 'Test junction',
  status: status,
  progress: status == JobStatus.completed ? 1 : .05,
  createdAt: DateTime.utc(2026, 10, 5),
  error: status == JobStatus.failed ? 'Video could not be decoded' : null,
);

class JobRepository extends DemoTrafficRepository {
  List<ProcessingJob> current = [job(JobStatus.queued)];
  bool offline = false;
  int reads = 0;
  int incidentReads = 0;

  @override
  Future<List<ProcessingJob>> getJobs() async {
    reads++;
    if (offline) throw StateError('Offline');
    return List.of(current);
  }

  @override
  Future<List<ViolationIncident>> getIncidents() async {
    incidentReads++;
    return super.getIncidents();
  }
}

void main() {
  testWidgets(
    'reopened queued job refreshes to completion and loads incidents',
    (tester) async {
      final repository = JobRepository();
      final store = TrafficStore(repository);
      addTearDown(store.dispose);
      await store.load();
      repository.current = [job(JobStatus.completed)];
      await tester.pump(const Duration(seconds: 2));
      expect(store.jobs.single.status, JobStatus.completed);
      expect(repository.incidentReads, 2);
      final reads = repository.reads;
      await tester.pump(const Duration(seconds: 4));
      expect(repository.reads, reads);
    },
  );

  testWidgets('network failure is visible and recovers without reupload', (
    tester,
  ) async {
    final repository = JobRepository();
    final store = TrafficStore(repository);
    addTearDown(store.dispose);
    await store.load();
    repository.offline = true;
    await tester.pump(const Duration(seconds: 2));
    expect(store.jobRefreshError, contains('Reconnecting'));
    expect(store.jobs.single.status, JobStatus.queued);
    repository.offline = false;
    repository.current = [job(JobStatus.processing)];
    await tester.pump(const Duration(seconds: 2));
      expect(store.jobs.single.status, JobStatus.processing);
      expect(store.jobRefreshError, isNull);
      repository.current = [job(JobStatus.completed)];
      await tester.pump(const Duration(seconds: 2));
      expect(store.jobs.single.status, JobStatus.completed);
  });

  testWidgets('temporary empty job list does not abandon polling', (
    tester,
  ) async {
    final repository = JobRepository();
    final store = TrafficStore(repository);
    addTearDown(store.dispose);
    await store.load();
    repository.current = [];
    await tester.pump(const Duration(seconds: 2));
    expect(store.jobs.single.status, JobStatus.queued);
    repository.current = [job(JobStatus.failed)];
    await tester.pump(const Duration(seconds: 2));
    expect(store.jobs.single.status, JobStatus.failed);
    expect(store.jobs.single.error, 'Video could not be decoded');
  });

  testWidgets('repeated load uses one poller and dispose cancels it', (
    tester,
  ) async {
    final repository = JobRepository();
    final store = TrafficStore(repository);
    await store.load();
    await store.load();
    await tester.pump(const Duration(seconds: 2));
    expect(repository.reads, 3);
    store.dispose();
    await tester.pump(const Duration(seconds: 4));
    expect(repository.reads, 3);
  });
}
