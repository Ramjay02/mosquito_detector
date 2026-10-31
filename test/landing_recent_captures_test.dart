import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosquito_detector/src/data/models.dart';
import 'package:mosquito_detector/src/data/surveillance_repository.dart';
import 'package:mosquito_detector/src/landing_page.dart';
import 'package:mosquito_detector/src/record_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Recent Captures', () {
    testWidgets('shows the empty state when there are no records', (
      WidgetTester tester,
    ) async {
      await _pumpLanding(tester, FakeRecentRepository());

      expect(
        find.text(
          'No captures yet. Scanned larvae appear here after you save them.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows exactly the five newest records with details', (
      WidgetTester tester,
    ) async {
      final FakeRecentRepository repository = FakeRecentRepository(
        records: <SurveillanceRecord>[
          for (int index = 1; index <= 7; index++) _record(index),
        ],
      );
      await _pumpLanding(tester, repository);

      expect(find.byType(RecordPhotoThumbnail), findsNWidgets(5));
      expect(find.text('Anopheles cracens'), findsNWidgets(5));
      expect(find.text('Barangay 7\n2026-10-25 14:07'), findsOneWidget);
      expect(find.text('Barangay 6\n2026-10-25 14:06'), findsOneWidget);
      expect(find.text('Barangay 5\n2026-10-25 14:05'), findsOneWidget);
      expect(find.text('Barangay 4\n2026-10-25 14:04'), findsOneWidget);
      expect(find.text('Barangay 3\n2026-10-25 14:03'), findsOneWidget);
      expect(find.text('Barangay 2\n2026-10-25 14:02'), findsNothing);
      expect(repository.lastLimit, 5);
    });

    testWidgets('a missing photo uses the shared placeholder', (
      WidgetTester tester,
    ) async {
      await _pumpLanding(
        tester,
        FakeRecentRepository(records: <SurveillanceRecord>[_record(1)]),
      );

      expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a capture opens its shared detail screen', (
      WidgetTester tester,
    ) async {
      final SurveillanceRecord record = _record(1);
      await _pumpLanding(
        tester,
        FakeRecentRepository(records: <SurveillanceRecord>[record]),
      );

      await tester.tap(find.byKey(const ValueKey<String>('recent-1')));
      await tester.pumpAndSettle();

      expect(find.byType(RecordDetailPage), findsOneWidget);
      expect(find.text('Species code: AN'), findsOneWidget);
      expect(find.text('Barangay: Barangay 1'), findsOneWidget);
    });

    testWidgets('reloads after the camera route returns', (
      WidgetTester tester,
    ) async {
      final FakeRecentRepository repository = FakeRecentRepository(
        records: <SurveillanceRecord>[_record(1)],
      );
      await _pumpLanding(
        tester,
        repository,
        cameraPageBuilder: (BuildContext context, String barangay) => Scaffold(
          body: TextButton(
            child: const Text('Return from camera'),
            onPressed: () {
              repository.records.add(_record(2));
              Navigator.of(context).pop();
            },
          ),
        ),
      );

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aguada (Pob.)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('SCAN LARVAE'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Return from camera'));
      await tester.pumpAndSettle();

      expect(find.text('Barangay 2\n2026-10-25 14:02'), findsOneWidget);
      expect(repository.queryCount, 2);
    });

    testWidgets('shows an error state if the repository query throws', (
      WidgetTester tester,
    ) async {
      await _pumpLanding(tester, FakeRecentRepository(shouldThrow: true));

      expect(find.text('Recent captures could not be loaded.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _pumpLanding(
  WidgetTester tester,
  FakeRecentRepository repository, {
  Widget Function(BuildContext context, String barangay)? cameraPageBuilder,
}) async {
  tester.view.physicalSize = const Size(900, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: LandingPage(
        repository: repository,
        cameraPageBuilder: cameraPageBuilder,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

SurveillanceRecord _record(int index) => SurveillanceRecord(
  id: index,
  sessionId: index,
  weekId: 1,
  imagePath: 'missing-$index.jpg',
  barangay: 'Barangay $index',
  captureTimestamp: DateTime(2026, 10, 25, 14, index),
  speciesCode: 'AN',
  anophelesCount: 1,
  createdAt: DateTime(2026, 10, 25, 14, index),
);

class FakeRecentRepository extends SurveillanceRepository {
  FakeRecentRepository({
    List<SurveillanceRecord> records = const <SurveillanceRecord>[],
    this.shouldThrow = false,
  }) : records = List<SurveillanceRecord>.of(records);

  List<SurveillanceRecord> records;
  final bool shouldThrow;
  int queryCount = 0;
  int? lastLimit;

  @override
  Future<List<SurveillanceRecord>> getRecentRecords({int limit = 5}) async {
    queryCount++;
    lastLimit = limit;
    if (shouldThrow) {
      throw StateError('fake query failure');
    }
    final List<SurveillanceRecord> newestFirst =
        List<SurveillanceRecord>.of(records)
          ..sort((SurveillanceRecord first, SurveillanceRecord second) {
            final int byTimestamp = second.captureTimestamp.compareTo(
              first.captureTimestamp,
            );
            if (byTimestamp != 0) {
              return byTimestamp;
            }
            return (second.id ?? 0).compareTo(first.id ?? 0);
          });
    return newestFirst.take(limit).toList();
  }
}
