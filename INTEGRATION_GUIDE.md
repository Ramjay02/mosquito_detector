# Aedes Logistic Regression — Flutter Integration Guide

## 1. What this package adds

This package embeds the trained logistic-regression inference into the existing Flutter application. It runs locally and does not call a server.

It adds:
- `assets/aedes_model_parameters.json`: exported `StandardScaler` and `LogisticRegression` parameters.
- `aedes_logistic_predictor.dart`: standardization, logistic score and sigmoid probability.
- `aedes_activity_repository.dart`: derives five weekly activity values from the app's local SQLite surveillance records, runs the predictor, and stores prediction history.
- `aedes_prediction_page.dart`: a compact page that invokes the real model instead of the current sample scenarios.

The existing camera, YOLO detector, MobileNet classifier, image storage, and offline workflow are not replaced.

## 2. Model definition

The model predicts whether Aedes aegypti activity will increase or decrease four weeks ahead.

The training target was defined as:
- `1` when `A_(t+4) > A_t` (Increase)
- `0` when `A_(t+4) < A_t` (Decrease)
- unchanged outcomes were excluded from training.

The model input order is **mandatory**:

| Position | Feature | Meaning |
|---:|---|---|
| 1 | `Lag_1` | Previous calendar week's positivity |
| 2 | `Lag_2` | Two calendar weeks before current week |
| 3 | `Lag_3` | Three calendar weeks before current week |
| 4 | `Lag_4` | Four calendar weeks before current week |
| 5 | `Current_Activity` | Current calendar week's positivity |

Weekly positivity is:

`Weekly Positivity = Positive Observed Days / Total Observed Days`

A day is positive if at least one processed `AG` (Aedes aegypti) classification is saved for that barangay on that date. A day is observed if at least one processed classification record exists for that barangay on that date. Multiple scans on the same date count as one observed day; any `AG` result makes that date positive.

**Important data assumption:** the current application stores a processed classification record for each saved scan. This implementation treats a non-`AG` processed classification as a negative observed day. Confirm this daily-status rule with City Health before operational use. If the app can save unknown/unclassified scans, exclude those from the observed-day denominator rather than treating them as negative.

## 3. Install into the existing repository

Copy the package folders into the root of your Flutter project, merging folders:
- `lib/src/prediction/`
- `assets/aedes_model_parameters.json`
- `test/` (optional contract test)

Do not overwrite the existing `assets/models/` folder.

### Update `pubspec.yaml`

Under `flutter: assets:`, add the JSON asset while preserving the existing model directory:

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/models/
    - assets/aedes_model_parameters.json
```

Then run:

```bash
flutter pub get
```

## 4. Prediction page wiring

The live Prediction tab is connected in `lib/src/app_shell.dart`, which builds
`AedesPredictionPage` from `lib/src/prediction/aedes_prediction_page.dart`.
`lib/src/prediction_page.dart` is only a re-export of that page; the old sample
page and its scenarios have been removed. The page loads the model when the
Prediction tab is selected and refreshes when `AppNavigation.recordsVersion`
changes.

## 5. Database compatibility

No destructive migration is required for this package. It creates a separate table named `aedes_direction_predictions` using `CREATE TABLE IF NOT EXISTS`.

It reads the existing `surveillance_records` columns:
- `barangay`
- `capture_timestamp`
- `species_code`
- `processing_status`

It uses `species_code = 'AG'` for Aedes aegypti, consistent with the repository's current species mapping. Existing `weekly_surveillance` count totals are not modified.

The prediction query is always scoped to the selected barangay. It does not combine data from different barangays.

## 6. Exact-week and missing-data handling

The implementation uses ISO calendar weeks beginning Monday. For a prediction made during the current week, it checks:
- four weeks before the current week,
- three weeks before,
- two weeks before,
- one week before,
- the current week.

Each of those five exact weeks must contain at least one observed day. A missing week returns `null`, displayed as **Insufficient data**. Missing observations are not converted to zero.

The query uses the device's current date by default. For controlled testing, call `predictForBarangay(..., referenceDate: DateTime(...))`.

## 7. Prediction formula

For each feature `x_i`, standardize using the training-set scaler:

`z_i = (x_i - mean_i) / scale_i`

Calculate the linear score:

`z = intercept + Σ(coefficient_i × z_i)`

Convert it to the probability of Increase:

`P(Increase) = 1 / (1 + exp(-z))`

Then:

`P(Decrease) = 1 - P(Increase)`

The predicted class is:
- class `1`: Increase, when `P(Increase) >= 0.50`
- class `0`: Decrease, when `P(Increase) < 0.50`

The `0.50` cutoff is the logistic classifier's default class boundary. It is not a validated threshold for initiating or stopping public-health interventions.

## 8. How new scan records affect predictions

The prediction does not use a single image directly as a logistic-regression input. The flow is:

1. User selects a barangay.
2. User captures or imports an image.
3. Existing YOLO/MobileNet pipeline classifies the larvae.
4. Existing repository saves the processed classification record with barangay and capture timestamp.
5. The prediction repository aggregates saved records by barangay and calendar date.
6. It calculates the positivity for the five required weeks.
7. It standardizes the five features and runs the embedded logistic-regression equation.
8. It saves the result and the five feature values locally.

A newly saved `AG` scan can change the current week's daily status and therefore its positivity. It does not automatically retrain the model. Model coefficients and scaler parameters remain fixed until a separately validated model update is installed.

## 9. Python-to-Dart parity validation (required)

Before relying on the Flutter output, compare the Dart implementation with the Python model for identical input rows.

In Python, using the exact saved training pipeline:

```python
import joblib

model = joblib.load("aedes_logistic_model.joblib")
X = [[0.5, 0.6, 0.7, 0.4, 0.55]]
print(model.predict_proba(X))
print(model.predict(X))
```

In Flutter, call:

```dart
final predictor = await AedesLogisticPredictor.load();
final result = predictor.predict([0.5, 0.6, 0.7, 0.4, 0.55]);
print(result.probabilityIncrease);
print(result.predictedClass);
```

The probabilities should match to a small floating-point tolerance (suggested: `1e-6`). Do not proceed if they do not match.

## 10. Recommended manual test cases

1. **Complete history:** one processed record exists in each of the five exact weeks. A probability and direction should be returned.
2. **Missing week:** remove all records for one of the five weeks. The page should display Insufficient data.
3. **Barangay isolation:** add records to Barangay A and Barangay B. Selecting A must never use B's records.
4. **Multiple scans same day:** several scans on one date count as one observed day.
5. **Positive day rule:** if at least one same-day record has `AG`, the date is positive.
6. **Non-Aedes day:** if there is a processed record but no `AG` record that date, it is negative under the current assumed rule.
7. **Offline operation:** turn off network connectivity and confirm the model still loads and predicts.
8. **New record:** save another processed record, rerun prediction, and confirm the daily/weekly activity input is recalculated.

## 11. Important limitations

- The historical training dataset had only 92 eligible rows from 13 barangays. The model should be treated as a prototype.
- A barangay not represented adequately in the training data may not generalize well. The current model JSON does not contain a per-barangay support count, so this package does not fabricate one.
- The app's existing classifier includes four classes (`AB`, `AG`, `AN`, `CQ`). This prediction uses only `AG` as the Aedes aegypti positive class.
- The model predicts direction of change in the weekly positivity metric. It does not predict larval counts, mosquito population density, dengue cases, or outbreak probability.
- The model is not retrained when new scans arrive.
- Results are decision-support information only. Follow City Health Office protocols and the judgement of qualified personnel.

## 12. Files included

- `lib/src/prediction/aedes_logistic_predictor.dart`
- `lib/src/prediction/aedes_activity_repository.dart`
- `lib/src/prediction/aedes_prediction_page.dart`
- `assets/aedes_model_parameters.json`
- `test/aedes_logistic_predictor_test.dart`
- `docs/INTEGRATION_GUIDE.md`

This is an integration package for the existing repository, not a complete standalone Flutter project.
