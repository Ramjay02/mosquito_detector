import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mosquito_detector/src/data/app_database.dart';
import 'package:mosquito_detector/src/data/surveillance_repository.dart';
import 'package:mosquito_detector/src/record_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resizePhotoForStorage', () {
    test('resizes a large image to a 1280px long side as JPEG', () async {
      final img.Image source = _noisyImage(2400, 1600);
      final Uint8List input = Uint8List.fromList(img.encodePng(source));

      final Uint8List output = await resizePhotoForStorage(input);
      final img.Image decoded = img.decodeImage(output)!;

      expect(mathMax(decoded.width, decoded.height), 1280);
      expect(decoded.width, 1280);
      expect(decoded.height, 853);
      expect(output.length, lessThan(input.length));
      expect(output[0], 0xff);
      expect(output[1], 0xd8);
    });

    test('does not upscale a small image', () async {
      final img.Image source = img.Image(width: 100, height: 60);
      final Uint8List output = await resizePhotoForStorage(
        Uint8List.fromList(img.encodePng(source)),
      );

      final img.Image decoded = img.decodeImage(output)!;
      expect(decoded.width, 100);
      expect(decoded.height, 60);
      expect(output[0], 0xff);
      expect(output[1], 0xd8);
    });
  });

  test(
    'saving writes a species-named JPEG and stores its existing path',
    () async {
      sqfliteFfiInit();
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'wayawaya_photo_',
      );
      final AppDatabase database = AppDatabase(
        factoryOverride: databaseFactoryFfi,
        databasesPathOverride: () async => tempDir.path,
      );
      final SurveillanceRepository repository = SurveillanceRepository(
        db: database,
        recordsDirectoryPathOverride: p.join(
          tempDir.path,
          'wayawaya',
          'records',
        ),
      );
      try {
        final img.Image source = _noisyImage(1600, 1000);
        final Uint8List input = Uint8List.fromList(img.encodePng(source));
        final DateTime capturedAt = DateTime(2026, 10, 25, 14, 30, 12);
        final saved = await repository.saveObservation(
          imageBytes: input,
          capturedAt: capturedAt,
          barangay: 'Aguada (Pob.)',
          speciesCode: 'AG',
        );

        expect(
          p.basename(saved.imagePath),
          matches(RegExp(r'^20261025_143012_AG\.jpg$')),
        );
        final File savedFile = File(saved.imagePath);
        expect(await savedFile.exists(), isTrue);
        expect(savedFile.lengthSync(), lessThan(input.length));
        expect(
          (await repository.recentRecords()).single.imagePath,
          saved.imagePath,
        );
      } finally {
        await database.close();
        await tempDir.delete(recursive: true);
      }
    },
  );

  testWidgets('missing thumbnail shows a neutral placeholder', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RecordPhotoThumbnail(imagePath: 'missing-photo.jpg'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

int mathMax(int first, int second) => first > second ? first : second;

img.Image _noisyImage(int width, int height) {
  final math.Random random = math.Random(27);
  final img.Image image = img.Image(width: width, height: height);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      image.setPixelRgb(
        x,
        y,
        random.nextInt(256),
        random.nextInt(256),
        random.nextInt(256),
      );
    }
  }
  return image;
}
