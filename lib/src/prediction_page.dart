import 'package:flutter/material.dart';

import 'constants.dart';
import 'data/prediction_sample.dart';

class PredictionPage extends StatefulWidget {
  const PredictionPage({super.key});

  @override
  State<PredictionPage> createState() => _PredictionPageState();
}

class _PredictionPageState extends State<PredictionPage> {
  String _barangay = kOzamizBarangays.first;
  int _scenarioIndex = 0;

  AedesOutlook get _outlook =>
      kSampleOutlooks[_scenarioIndex].forBarangay(_barangay);

  @override
  Widget build(BuildContext context) {
    final AedesOutlook outlook = _outlook;
    final double? currentPresence = outlook.current.presence;
    final double? probability = outlook.probabilityIncrease;
    final String status = probability == null
        ? 'Insufficient data'
        : aedesOutlookStatus(probability);
    final IconData statusIcon = _statusIconFor(probability);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prediction'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Aedes aegypti outlook',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            const Text(
              'Chance that Aedes aegypti presence will increase or decrease 4 weeks from now',
            ),
            const SizedBox(height: 16),
            const _SampleBanner(),
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
                if (value != null) {
                  setState(() => _barangay = value);
                }
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Preview (sample)'),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: List<Widget>.generate(4, (int index) {
                        final String label = 'S${index + 1}';
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(label),
                            selected: _scenarioIndex == index,
                            onSelected: (_) =>
                                setState(() => _scenarioIndex = index),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _sectionCard(
              title: 'This week',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aedes aegypti found on ${outlook.current.positiveDays} of '
                    '${outlook.current.observedDays} observed days '
                    '(${_formatPresence(currentPresence)})',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Weekly presence = share of observed days with Aedes aegypti found',
                  ),
                ],
              ),
            ),
            _sectionCard(
              title: '4-week outlook',
              child: probability == null
                  ? _insufficientData(outlook.missingWeeks)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${(probability * 100).round()}%',
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        const Text('chance of increase'),
                        const SizedBox(height: 12),
                        _DirectionBar(probability: probability),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(statusIcon, size: 22),
                            const SizedBox(width: 8),
                            Text(
                              status,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'The model estimates the DIRECTION of change, not the number of larvae.',
                        ),
                        if (outlook.limitedEvidence) ...[
                          const SizedBox(height: 12),
                          const _LimitedEvidenceBadge(),
                        ],
                      ],
                    ),
            ),
            _sectionCard(
              title: 'Inputs used',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <WeekObservation>[
                  outlook.current,
                  ...outlook.previous,
                ].map(_inputChip).toList(),
              ),
            ),
            _sectionCard(
              title: 'Last 5 weeks',
              child: _FiveWeekChart(
                observations: <WeekObservation>[
                  ...outlook.previous.reversed,
                  outlook.current,
                ],
              ),
            ),
            _sectionCard(
              title: 'Recommended actions',
              child: Text(_recommendation(currentPresence, probability)),
            ),
            _sectionCard(
              title: 'About this prediction',
              child: const Text(
                'This preliminary model was trained on limited historical data. '
                'It predicts the direction of change 4 weeks ahead and needs '
                'observations in the current week and the 4 previous weeks. '
                '0.5 is not a validated threshold.',
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 12),
              child: Center(
                child: Text(
                  'General suggestions only. Follow City Health Office protocols.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inputChip(WeekObservation observation) {
    final double? presence = observation.presence;
    return Chip(
      label: Text(
        presence == null
            ? '${observation.weekLabel}: No data'
            : '${observation.weekLabel}: ${_formatPresence(presence)} '
                  '(${observation.positiveDays}/${observation.observedDays} days)',
      ),
    );
  }

  Widget _insufficientData(List<String> missingWeeks) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Icon(Icons.info_outline),
          const SizedBox(width: 8),
          Text(
            'Insufficient data',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
      const SizedBox(height: 8),
      const Text('No probability is available. Missing observations for:'),
      ...missingWeeks.map((String week) => Text('• $week')),
    ],
  );

  IconData _statusIconFor(double? probability) {
    if (probability == null) {
      return Icons.info_outline;
    }
    if (probability >= likelyIncreaseMin) {
      return Icons.trending_up;
    }
    if (probability <= likelyDecreaseMax) {
      return Icons.trending_down;
    }
    return Icons.help_outline;
  }

  String _recommendation(double? presence, double? probability) {
    if (probability == null) {
      return 'Collect observations for the missing weeks, then review again.';
    }
    if (probability >= likelyIncreaseMin) {
      if (presence != null && presence >= highPresenceMin) {
        return 'Intensify search-and-destroy of breeding sites; schedule '
            'house-to-house inspection and clean-up drives; remind households '
            'to cover, empty and scrub water containers weekly; inform barangay '
            'health workers and the City Health Office; scan more days this week.';
      }
      return 'Act early: keep weekly surveillance, check container hotspots '
          '(tires, drums, pots), start community reminders.';
    }
    if (probability <= likelyDecreaseMax) {
      if (presence != null && presence >= highPresenceMin) {
        return 'Do not relax yet: continue control activities until presence '
            'stays low for several weeks.';
      }
      return 'Maintain routine surveillance and community reminders.';
    }
    return 'The outlook is unclear: continue routine surveillance, add '
        'observation days this week and review again next week.';
  }

  static String _formatPresence(double? presence) =>
      presence == null ? 'No data' : '${(presence * 100).round()}%';

  Widget _sectionCard({required String title, required Widget child}) => Card(
    margin: const EdgeInsets.only(top: 8),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

class _SampleBanner extends StatelessWidget {
  const _SampleBanner();

  @override
  Widget build(BuildContext context) => const MaterialBanner(
    content: Text(
      'SAMPLE DATA - the prediction model is not connected yet. For decision '
      'support only. Final decisions belong to trained health personnel.',
    ),
    leading: Icon(Icons.science_outlined),
    actions: <Widget>[SizedBox.shrink()],
  );
}

class _LimitedEvidenceBadge extends StatelessWidget {
  const _LimitedEvidenceBadge();

  @override
  Widget build(BuildContext context) => const Chip(
    avatar: Icon(Icons.info_outline),
    label: Text(
      "Limited evidence: this barangay is not well represented in the model's training data.",
    ),
  );
}

class _DirectionBar extends StatelessWidget {
  const _DirectionBar({required this.probability});

  final double probability;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 18,
            child: Row(
              children: [
                Expanded(
                  flex: (probability * 1000).round(),
                  child: ColoredBox(color: colors.primary),
                ),
                Expanded(
                  flex: ((1 - probability) * 1000).round(),
                  child: ColoredBox(color: colors.tertiary),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Increase ${(probability * 100).round()}%  ·  '
          'Decrease ${((1 - probability) * 100).round()}%',
        ),
      ],
    );
  }
}

class _FiveWeekChart extends StatelessWidget {
  const _FiveWeekChart({required this.observations});

  final List<WeekObservation> observations;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: observations.map((WeekObservation observation) {
        final double? presence = observation.presence;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  height: 88,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: presence == null
                        ? Container(
                            height: 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'no data',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11),
                            ),
                          )
                        : Container(
                            height: (presence * 80).clamp(4, 80),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _shortWeek(observation.weekLabel),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                if (presence != null)
                  Text(
                    '${(presence * 100).round()}%',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  String _shortWeek(String label) {
    if (label == 'This week') {
      return 'This week';
    }
    return label
        .replaceFirst(' weeks ago', 'w ago')
        .replaceFirst(' week ago', 'w ago');
  }
}
