class WeekObservation {
  const WeekObservation({
    required this.weekLabel,
    required this.positiveDays,
    required this.observedDays,
  });

  final String weekLabel;
  final int positiveDays;
  final int observedDays;

  double? get presence =>
      observedDays == 0 ? null : positiveDays / observedDays;
}

class AedesOutlook {
  const AedesOutlook({
    required this.barangay,
    required this.current,
    required this.previous,
    required this.probabilityIncrease,
    required this.limitedEvidence,
    required this.missingWeeks,
  });

  final String barangay;
  final WeekObservation current;
  final List<WeekObservation> previous;
  final double? probabilityIncrease;
  final bool limitedEvidence;
  final List<String> missingWeeks;

  AedesOutlook forBarangay(String value) => AedesOutlook(
    barangay: value,
    current: current,
    previous: previous,
    probabilityIncrease: probabilityIncrease,
    limitedEvidence: limitedEvidence,
    missingWeeks: missingWeeks,
  );
}

// Placeholder thresholds, not validated.
const double likelyIncreaseMin = 0.60;
const double likelyDecreaseMax = 0.40;
const double highPresenceMin = 0.50;

String aedesOutlookStatus(double probabilityIncrease) {
  if (probabilityIncrease >= likelyIncreaseMin) {
    return 'Likely increase';
  }
  if (probabilityIncrease <= likelyDecreaseMax) {
    return 'Likely decrease';
  }
  return 'Uncertain';
}

const List<AedesOutlook> kSampleOutlooks = <AedesOutlook>[
  AedesOutlook(
    barangay: 'Aguada (Pob.)',
    current: WeekObservation(
      weekLabel: 'This week',
      positiveDays: 1,
      observedDays: 3,
    ),
    previous: <WeekObservation>[
      WeekObservation(
        weekLabel: '1 week ago',
        positiveDays: 1,
        observedDays: 2,
      ),
      WeekObservation(
        weekLabel: '2 weeks ago',
        positiveDays: 1,
        observedDays: 3,
      ),
      WeekObservation(
        weekLabel: '3 weeks ago',
        positiveDays: 1,
        observedDays: 2,
      ),
      WeekObservation(
        weekLabel: '4 weeks ago',
        positiveDays: 2,
        observedDays: 3,
      ),
    ],
    probabilityIncrease: 0.74,
    limitedEvidence: true,
    missingWeeks: <String>[],
  ),
  AedesOutlook(
    barangay: 'Aguada (Pob.)',
    current: WeekObservation(
      weekLabel: 'This week',
      positiveDays: 3,
      observedDays: 3,
    ),
    previous: <WeekObservation>[
      WeekObservation(
        weekLabel: '1 week ago',
        positiveDays: 2,
        observedDays: 2,
      ),
      WeekObservation(
        weekLabel: '2 weeks ago',
        positiveDays: 2,
        observedDays: 3,
      ),
      WeekObservation(
        weekLabel: '3 weeks ago',
        positiveDays: 2,
        observedDays: 3,
      ),
      WeekObservation(
        weekLabel: '4 weeks ago',
        positiveDays: 1,
        observedDays: 1,
      ),
    ],
    probabilityIncrease: 0.20,
    limitedEvidence: false,
    missingWeeks: <String>[],
  ),
  AedesOutlook(
    barangay: 'Aguada (Pob.)',
    current: WeekObservation(
      weekLabel: 'This week',
      positiveDays: 1,
      observedDays: 2,
    ),
    previous: <WeekObservation>[
      WeekObservation(
        weekLabel: '1 week ago',
        positiveDays: 2,
        observedDays: 3,
      ),
      WeekObservation(
        weekLabel: '2 weeks ago',
        positiveDays: 1,
        observedDays: 2,
      ),
      WeekObservation(
        weekLabel: '3 weeks ago',
        positiveDays: 1,
        observedDays: 1,
      ),
      WeekObservation(
        weekLabel: '4 weeks ago',
        positiveDays: 2,
        observedDays: 3,
      ),
    ],
    probabilityIncrease: 0.58,
    limitedEvidence: false,
    missingWeeks: <String>[],
  ),
  AedesOutlook(
    barangay: 'Aguada (Pob.)',
    current: WeekObservation(
      weekLabel: 'This week',
      positiveDays: 2,
      observedDays: 3,
    ),
    previous: <WeekObservation>[
      WeekObservation(
        weekLabel: '1 week ago',
        positiveDays: 1,
        observedDays: 2,
      ),
      WeekObservation(
        weekLabel: '2 weeks ago',
        positiveDays: 0,
        observedDays: 0,
      ),
      WeekObservation(
        weekLabel: '3 weeks ago',
        positiveDays: 0,
        observedDays: 0,
      ),
      WeekObservation(
        weekLabel: '4 weeks ago',
        positiveDays: 1,
        observedDays: 1,
      ),
    ],
    probabilityIncrease: null,
    limitedEvidence: false,
    missingWeeks: <String>['2 weeks ago', '3 weeks ago'],
  ),
];
