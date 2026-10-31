import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'constants.dart';
import 'app_navigation.dart';
import 'data/models.dart';
import 'data/surveillance_repository.dart';
import 'record_widgets.dart';

class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key, required this.repository, this.navigation});

  final SurveillanceRepository repository;
  final AppNavigation? navigation;

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  late Future<_RecordsData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    widget.navigation?.selectedTab.addListener(_onTabChanged);
    widget.navigation?.recordsVersion.addListener(_onRecordsChanged);
  }

  @override
  void didUpdateWidget(covariant RecordsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigation != widget.navigation) {
      oldWidget.navigation?.selectedTab.removeListener(_onTabChanged);
      oldWidget.navigation?.recordsVersion.removeListener(_onRecordsChanged);
      widget.navigation?.selectedTab.addListener(_onTabChanged);
      widget.navigation?.recordsVersion.addListener(_onRecordsChanged);
    }
  }

  @override
  void dispose() {
    widget.navigation?.selectedTab.removeListener(_onTabChanged);
    widget.navigation?.recordsVersion.removeListener(_onRecordsChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (widget.navigation?.selectedTab.value == 1) {
      _refresh();
    }
  }

  void _onRecordsChanged() {
    if (widget.navigation?.selectedTab.value == 1) {
      _refresh();
    }
  }

  Future<_RecordsData> _load() async {
    final List<SurveillanceRecord> records = await widget.repository
        .recentRecords();
    final List<WeeklySurveillance> weeks = await widget.repository
        .weeklySeries();
    final int total = await widget.repository.recordCount();
    return _RecordsData(records: records, weeks: weeks, total: total);
  }

  Future<void> _refresh() async {
    final Future<_RecordsData> future = _load();
    setState(() {
      _future = future;
    });
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Surveillance Records'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: FutureBuilder<_RecordsData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Failed to load records:\n${snapshot.error}'),
              ),
            );
          }
          final _RecordsData data = snapshot.data!;
          if (data.records.isEmpty) {
            return const Center(child: Text('No surveillance records yet.'));
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                _WeeklySummary(weeks: data.weeks, totalRecords: data.total),
                const SizedBox(height: 8),
                ...data.records.map(_RecordTile.new),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RecordsData {
  const _RecordsData({
    required this.records,
    required this.weeks,
    required this.total,
  });

  final List<SurveillanceRecord> records;
  final List<WeeklySurveillance> weeks;
  final int total;
}

class _WeeklySummary extends StatelessWidget {
  const _WeeklySummary({required this.weeks, required this.totalRecords});

  final List<WeeklySurveillance> weeks;
  final int totalRecords;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            'Weekly Surveillance',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (weeks.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No weekly aggregates yet.'),
            ),
          )
        else
          ...weeks.reversed.map(
            (WeeklySurveillance week) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Period: ${week.label}'),
                    Text('Barangay: ${week.barangay}'),
                    const SizedBox(height: 4),
                    Text('Aedes albopictus ${week.aedesAlbopictusCount}'),
                    Text('Aedes aegypti ${week.aedesAegyptiCount}'),
                    Text('Culex ${week.culexCount}'),
                    Text('Anopheles ${week.anophelesCount}'),
                  ],
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text('Total records stored: $totalRecords'),
        ),
      ],
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile(this.record);

  final SurveillanceRecord record;

  @override
  Widget build(BuildContext context) {
    final DateFormat format = DateFormat('yyyy-MM-dd HH:mm');
    final int speciesIndex = kSpeciesCodes.indexOf(record.speciesCode);
    final String speciesName = speciesIndex >= 0
        ? kSpeciesFullNames[speciesIndex]
        : record.speciesCode;
    return Card(
      child: ListTile(
        leading: RecordPhotoThumbnail(imagePath: record.imagePath),
        title: Text(speciesName),
        subtitle: Text(
          '${format.format(record.captureTimestamp)}\n${record.barangay}',
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
