import 'package:flutter/material.dart';

import '../app_navigation.dart';
import '../constants.dart';
import 'aedes_activity_repository.dart';
import 'aedes_logistic_predictor.dart';

class AedesPredictionPage extends StatefulWidget {
  const AedesPredictionPage({super.key, this.navigation, this.repository});

  final AppNavigation? navigation;
  final AedesActivityRepository? repository;

  @override
  State<AedesPredictionPage> createState() => _AedesPredictionPageState();
}

class _PredictionState {
  const _PredictionState({
    required this.prediction,
    required this.hasObservations,
  });

  final BarangayPrediction? prediction;
  final bool hasObservations;
}

class _AedesPredictionPageState extends State<AedesPredictionPage> {
  String _barangay = kOzamizBarangays.first;
  Future<AedesActivityRepository>? _repository;
  Future<_PredictionState>? _prediction;

  @override
  void initState() {
    super.initState();
    if (widget.repository != null) {
      _repository = Future<AedesActivityRepository>.value(widget.repository);
    }
    widget.navigation?.selectedTab.addListener(_onTabChanged);
    widget.navigation?.recordsVersion.addListener(_onRecordsChanged);
    if (widget.navigation == null ||
        widget.navigation!.selectedTab.value == 2) {
      _repository ??= _loadRepository();
      _prediction = _loadPrediction();
    }
  }

  Future<AedesActivityRepository> _loadRepository() async {
    final predictor = await AedesLogisticPredictor.load();
    return AedesActivityRepository(predictor: predictor);
  }

  @override
  void didUpdateWidget(covariant AedesPredictionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _repository = widget.repository == null
          ? null
          : Future<AedesActivityRepository>.value(widget.repository);
      _prediction = null;
    }
    if (oldWidget.navigation != widget.navigation) {
      oldWidget.navigation?.selectedTab.removeListener(_onTabChanged);
      oldWidget.navigation?.recordsVersion.removeListener(_onRecordsChanged);
      widget.navigation?.selectedTab.addListener(_onTabChanged);
      widget.navigation?.recordsVersion.addListener(_onRecordsChanged);
      if (widget.navigation == null ||
          widget.navigation!.selectedTab.value == 2) {
        _refresh();
      }
    } else if (oldWidget.repository != widget.repository &&
        widget.repository != null) {
      _refresh();
    }
  }

  @override
  void dispose() {
    widget.navigation?.selectedTab.removeListener(_onTabChanged);
    widget.navigation?.recordsVersion.removeListener(_onRecordsChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (widget.navigation?.selectedTab.value == 2) {
      _refresh();
    }
  }

  void _onRecordsChanged() {
    if (widget.navigation?.selectedTab.value == 2) {
      _refresh();
    }
  }

  Future<_PredictionState> _loadPrediction() async {
    final Future<AedesActivityRepository> repositoryFuture = _repository ??=
        _loadRepository();
    final AedesActivityRepository repository = await repositoryFuture;
    final BarangayPrediction? prediction = await repository.predictForBarangay(
      _barangay,
    );
    if (prediction != null) {
      return _PredictionState(prediction: prediction, hasObservations: true);
    }
    final bool hasObservations = await repository.hasObservationsForBarangay(
      _barangay,
    );
    return _PredictionState(prediction: null, hasObservations: hasObservations);
  }

  void _refresh() {
    setState(() {
      _repository ??= _loadRepository();
      _prediction = _loadPrediction();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prediction'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Refresh prediction',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _repository == null
          ? _message(
              'Select the Prediction tab to load this barangay\'s prediction.',
            )
          : FutureBuilder<AedesActivityRepository>(
              future: _repository,
              builder: (context, repoSnapshot) {
                if (repoSnapshot.hasError) {
                  return _message(
                    'Model loading failed:\n${repoSnapshot.error}',
                  );
                }
                if (!repoSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Weekly Aedes aegypti positivity direction four weeks ahead',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      key: const ValueKey<String>('prediction-barangay'),
                      initialValue: _barangay,
                      decoration: const InputDecoration(labelText: 'Barangay'),
                      items: kOzamizBarangays
                          .map(
                            (String name) => DropdownMenuItem<String>(
                              value: name,
                              child: Text(name),
                            ),
                          )
                          .toList(),
                      onChanged: (String? value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _barangay = value;
                          _prediction = _loadPrediction();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    if (_prediction == null)
                      _message(
                        'Select the Prediction tab to load this barangay\'s prediction.',
                      )
                    else
                      FutureBuilder<_PredictionState>(
                        future: _prediction,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          if (snapshot.hasError) {
                            return _message(
                              'Prediction failed:\n${snapshot.error}',
                            );
                          }
                          final _PredictionState state = snapshot.data!;
                          final BarangayPrediction? result = state.prediction;
                          if (result == null && !state.hasObservations) {
                            return _message(
                              'No saved processed observations for this barangay in the current week and four preceding weeks.',
                            );
                          }
                          if (result == null) {
                            return _message(
                              'Insufficient data. This barangay needs at least one processed observation in each of the current ISO week and the four exact preceding weeks. Missing weeks are not treated as zero.',
                            );
                          }
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    result.prediction.direction,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'P(Increase): ${(result.prediction.probabilityIncrease * 100).toStringAsFixed(1)}%',
                                  ),
                                  Text(
                                    'Predicted direction: ${result.prediction.direction}',
                                  ),
                                  const Divider(height: 24),
                                  Text(
                                    'Weekly observations — ${result.barangay}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  for (int i = 0; i < result.weeks.length; i++)
                                    Text(
                                      '${_weekLabel(i)}: ${result.weeks[i].positiveDays}/${result.weeks[i].observedDays} positive/observed days '
                                      '(${(result.weeks[i].positivity * 100).toStringAsFixed(1)}%)',
                                    ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Feature values used',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  for (
                                    int i = 0;
                                    i <
                                        AedesLogisticPredictor
                                            .featureOrder
                                            .length;
                                    i++
                                  )
                                    Text(
                                      '${AedesLogisticPredictor.featureOrder[i]}: ${result.modelInputs[i].toStringAsFixed(6)}',
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 12),
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Limited evidence: the selected barangay may not have been represented in the model training data.',
                        ),
                      ),
                    ),
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Decision-support for weekly Aedes aegypti positivity direction four weeks ahead only; this is not a count, population-density estimate, or outbreak forecast. The prototype was trained on 92 eligible rows from 13 barangays and does not retrain when new scans arrive. Follow City Health Office protocols.',
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  String _weekLabel(int index) {
    if (index == 4) {
      return 'Current week';
    }
    return '${4 - index} week${index == 3 ? '' : 's'} before';
  }

  Widget _message(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Card(
        child: Padding(padding: const EdgeInsets.all(16), child: Text(message)),
      ),
    ),
  );
}
