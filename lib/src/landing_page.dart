import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app_navigation.dart';
import 'constants.dart';
import 'camera_page.dart';
import 'data/models.dart';
import 'data/surveillance_repository.dart';
import 'record_widgets.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({
    super.key,
    this.navigation,
    this.repository,
    this.cameraPageBuilder,
  });

  final AppNavigation? navigation;
  final SurveillanceRepository? repository;
  final Widget Function(BuildContext context, String barangay)?
  cameraPageBuilder;

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  late final AppNavigation _navigation = widget.navigation ?? appNavigation;
  late final SurveillanceRepository _repository =
      widget.repository ?? SurveillanceRepository();
  late Future<List<SurveillanceRecord>> _recentRecords;
  String? _selectedBarangay;

  @override
  void initState() {
    super.initState();
    _recentRecords = _repository.getRecentRecords(limit: 5);
  }

  void _reloadRecentRecords() {
    setState(() {
      _recentRecords = _repository.getRecentRecords(limit: 5);
    });
  }

  Future<void> _openCamera() async {
    final String? barangay = _selectedBarangay;
    if (barangay == null) {
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (context) =>
            widget.cameraPageBuilder?.call(context, barangay) ??
            CameraPage(barangay: barangay),
      ),
    );
    if (mounted) {
      _reloadRecentRecords();
    }
  }

  void _openRecords() {
    _navigation.selectTab(1);
  }

  @override
  Widget build(BuildContext context) {
    // Colors extracted directly from camera_page.dart
    const Color primaryCyan = Color(0xFF00E5FF);
    const Color overlayBlack = Colors.black54;

    return Scaffold(
      backgroundColor: Colors.black, // Matches camera background
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Waya-waya Scanner',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () {},
            tooltip: 'Sync Data',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Active Surveillance Area',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              color: overlayBlack, // Using the camera's overlay color
              shape: RoundedRectangleBorder(
                side: const BorderSide(
                  color: primaryCyan,
                  width: 1,
                ), // Cyan border highlight
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    dropdownColor: Colors.black87,
                    isExpanded: true,
                    hint: const Text(
                      'Select Barangay',
                      style: TextStyle(color: Colors.white70),
                    ),
                    value: _selectedBarangay,
                    icon: const Icon(Icons.location_on, color: primaryCyan),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    items: kOzamizBarangays.map((String barangay) {
                      return DropdownMenuItem<String>(
                        value: barangay,
                        child: Text(barangay),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedBarangay = newValue;
                      });
                    },
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 72,
              child: FilledButton.icon(
                onPressed: _selectedBarangay == null ? null : _openCamera,
                icon: Icon(
                  Icons.camera_alt,
                  size: 28,
                  color: _selectedBarangay == null
                      ? Colors.white54
                      : Colors.black,
                ),
                label: Text(
                  'SCAN LARVAE',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: _selectedBarangay == null
                        ? Colors.white54
                        : Colors.black,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor:
                      primaryCyan, // Main action uses the cyan reticle color
                  disabledBackgroundColor: overlayBlack,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent Captures',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
                TextButton(
                  onPressed: _openRecords,
                  child: const Text('See all'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<SurveillanceRecord>>(
                future: _recentRecords,
                builder:
                    (
                      BuildContext context,
                      AsyncSnapshot<List<SurveillanceRecord>> snapshot,
                    ) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(
                          child: SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      if (snapshot.hasError) {
                        return const Center(
                          child: Text(
                            'Recent captures could not be loaded.',
                            style: TextStyle(color: Colors.white70),
                          ),
                        );
                      }
                      final List<SurveillanceRecord> records =
                          snapshot.data ?? const <SurveillanceRecord>[];
                      if (records.isEmpty) {
                        return const Center(
                          child: Text(
                            'No captures yet. Scanned larvae appear here after you save them.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70),
                          ),
                        );
                      }
                      return ListView(
                        padding: EdgeInsets.zero,
                        children: records.map(_recentCaptureTile).toList(),
                      );
                    },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recentCaptureTile(SurveillanceRecord record) {
    final DateFormat format = DateFormat('yyyy-MM-dd HH:mm');
    final int speciesIndex = kSpeciesCodes.indexOf(record.speciesCode);
    final String speciesName = speciesIndex >= 0
        ? kSpeciesFullNames[speciesIndex]
        : record.speciesCode;
    return Card(
      color: Colors.black54,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        key: ValueKey<String>('recent-${record.id}'),
        leading: RecordPhotoThumbnail(imagePath: record.imagePath),
        title: Text(speciesName, style: const TextStyle(color: Colors.white)),
        subtitle: Text(
          '${record.barangay}\n${format.format(record.captureTimestamp)}',
          style: const TextStyle(color: Colors.white70),
        ),
        onTap: () {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => RecordDetailPage(record: record),
            ),
          );
        },
      ),
    );
  }
}
