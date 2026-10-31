import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'constants.dart';
import 'data/models.dart';

class RecordPhotoThumbnail extends StatefulWidget {
  const RecordPhotoThumbnail({super.key, required this.imagePath});

  final String imagePath;

  @override
  State<RecordPhotoThumbnail> createState() => _RecordPhotoThumbnailState();
}

class _RecordPhotoThumbnailState extends State<RecordPhotoThumbnail> {
  late final Future<bool> _fileExists = File(widget.imagePath).exists();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox.square(
        dimension: 64,
        child: FutureBuilder<bool>(
          future: _fileExists,
          builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
            if (snapshot.data != true) {
              return _photoPlaceholder;
            }
            return Image.file(
              File(widget.imagePath),
              cacheWidth: 200,
              fit: BoxFit.cover,
              errorBuilder: (
                BuildContext context,
                Object error,
                StackTrace? stack,
              ) => _photoPlaceholder,
            );
          },
        ),
      ),
    );
  }

  Widget get _photoPlaceholder => const ColoredBox(
    color: Color(0xFF424242),
    child: Center(
      child: Icon(Icons.image_not_supported_outlined, color: Colors.white70),
    ),
  );
}

class RecordDetailPage extends StatelessWidget {
  const RecordDetailPage({super.key, required this.record});

  final SurveillanceRecord record;

  @override
  Widget build(BuildContext context) {
    final int speciesIndex = kSpeciesCodes.indexOf(record.speciesCode);
    final String speciesName = speciesIndex >= 0
        ? kSpeciesFullNames[speciesIndex]
        : record.speciesCode;
    final String date = DateFormat('yyyy-MM-dd HH:mm')
        .format(record.captureTimestamp);

    return Scaffold(
      appBar: AppBar(title: Text(speciesName)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Image.file(
                    File(record.imagePath),
                    cacheWidth: 1200,
                    fit: BoxFit.contain,
                    errorBuilder:
                        (
                          BuildContext context,
                          Object error,
                          StackTrace? stack,
                        ) => const Center(
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            size: 72,
                            color: Colors.white54,
                          ),
                        ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(speciesName, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Species code: ${record.speciesCode}'),
            Text('Date: $date'),
            Text('Barangay: ${record.barangay}'),
          ],
        ),
      ),
    );
  }
}
