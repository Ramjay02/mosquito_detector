# Waya-waya Scanner Codebase Guide
j
Last updated: 2026-11-17

## Changelog

- 2026-11-17: Added on-device Aedes logistic-regression prediction (replaces static sample page).

## Overview and app flow

Waya-waya Scanner is a Flutter app that detects and classifies mosquito larvae in phone photos taken with a clip-on microscope lens. The package name remains `mosquito_detector`, and the visible app name is `Waya-waya Scanner`.

`main.dart` creates a dark Material 3 `MaterialApp` under the `_AuthApp` root
auth gate. Bootstrap shows a splash screen, then Login while signed out,
Account Created when verification requires acknowledgement, or
`lib/src/app_shell.dart` when signed in. The shell uses an `IndexedStack` to
keep four tabs alive in this order: Home, Records, Prediction, and Profile.
Its icon-only Material 3 `NavigationBar` stays visible at the bottom of tab
pages and respects the system gesture area. Selecting a tab changes the stack
index without recreating the other tab states.

`lib/src/app_navigation.dart` contains the small, resettable navigation state:
`selectedTab` chooses the current tab and `recordsVersion` notifies the Records
and Prediction tabs that saved records changed. Back on a non-Home tab returns
to Home; Home allows the normal route/app back behavior. Camera, result, and
record-detail screens are pushed above the shell, so they cover the bottom bar.

Home uses `lib/src/landing_page.dart`. It requires a selection from the 51
Ozamiz City barangays in `kOzamizBarangays` before scanning. The “See all”
action in Recent Captures selects the Records tab; there is no separate Records
button on Home. Recent Captures queries saved records and shows up to five
newest captures from all barangays.

The app flow is:

1. Home: select a barangay, scan, or view recent captures.
2. Camera: capture or pick from gallery, preprocess and detect, then push the
   result screen.
3. Result: validate and classify, and save only when the user explicitly taps
   Save.
4. Records: view saved observations, weekly totals, and photo details.
5. Prediction: run the on-device logistic-regression model from local saved
   observations. Profile displays the signed-in account and authentication
   status.

Location collection, permissions, and geolocation code have been removed. No
geolocator dependency or location fields exist in the current UI or database
schema.

## Preprocessing pipeline

The preprocessing pipeline is implemented in `lib/src/preprocess.dart` and is designed to mirror the OpenCV training pipeline.

### 1) Stretch to 640x640
The input image is stretched directly to 640x640 with no letterbox.

### 2) Gray-world white balance
- Compute the overall mean and per-channel means.
- Scale each channel by `overall_mean / channel_mean`.
- Clip to 255.
- Truncate to 8-bit integer values.

### 3) CLAHE on LAB
- Convert to LAB in OpenCV-style space.
- Apply to the L channel only.
- Convert L back from `L*255/100`, using `a+128` and `b+128` as stored values.
- Use 8x8 tiles with clip limit `int(2.0 * tileArea / 256)`.
- Redistribute clipped counts and build the LUT using cumulative counts.
- Interpolate between the four nearest tile LUTs using the tile-space interpolation described in the pipeline.

### 4) Unsharp mask
- Apply a 7-tap Gaussian blur with sigma 1.0.
- Use reflect-101 border handling.
- Compute `out = clip(round(1.4 * img - 0.4 * blur), 0, 255)`.

### 5) Crop and focus score
- Cropping uses the same processed 640x640 frame used by detection.
- The crop function applies a 10% margin, truncates coordinates, and replicates border pixels to square the target crop.
- Resize to 224x224 using area averaging when shrinking and bicubic A=-0.75 when enlarging.
- The focus score is the variance of the 4-neighbour Laplacian on the grayscale stretched image.

This pipeline intentionally does not do min-max normalization, does not add a separate blur step, and does not letterbox the detector input.

## Detector and decoder

The detector is a YOLOv8n model at `assets/models/yolov8n.tflite`.

### Model contract
- Input: float32 `[1, 3, 640, 640]` NCHW, RGB, values in `[0, 1]`.
- Output: float32 `[1, 8, 8400]`, channel-first order: `cx, cy, w, h, score_AB, score_AG, score_AN, score_CQ`.

### Decoder behavior
The decoder in `lib/src/yolo_decoder.dart`:
- infers whether boxes are normalized or pixel units automatically per photo,
- checks anchors against the best class score threshold,
- filters by confidence and applies NMS,
- returns boxes in original photo-pixel coordinates,
- keeps up to the configured limit of detections for display and validation.

The app currently allows more than one detection to be visible during analysis (`maxDetections` is configured to permit up to 3 candidates), but classification and counting remain governed by the single best valid detection rule.

## Classifier and crop rules

The classifier is `assets/models/mobilenetv3.tflite`.

### Model contract
- Input: float32 NHWC `[1, 224, 224, 3]` in the 0-255 range.
- Output: float32 `[1, 4]` for AB, AG, AN, CQ.
- The output is already softmax in the verified model; the code still passes through probabilities if they are already a valid distribution, otherwise it applies softmax.
- No input scaling by `1/255` or mean/std normalization is used.

### Crop source
Classification uses the same processed 640x640 frame that detection already used. The engine keeps that frame together with the original image bytes, and the crop is produced from the processed frame, not recomputed from the original photo.

Shared crop logic covers:
- 10% margin,
- truncated coordinates,
- edge-replicated square padding,
- 224x224 resize,
- no crop for boxes smaller than 16 px.

## Species and result rules

Species codes and order:
- `AB` = Aedes albopictus
- `AG` = Aedes aegypti
- `AN` = Anopheles cracens
- `CQ` = Culex quinquefasciatus

The app expects one larva per photo. Result handling is:

1. No detection → show “No larva detected - retake photo”; save nothing.
2. A second detection at or above `EXTRA_LARVA_CONF` (0.50) → show “More than one larva detected. Photograph them one at a time.”; save nothing.
3. Classifier confidence below 0.70 → show the classifier guess and confidence; save nothing.
4. Otherwise: show the full species name, confidence, and detector class. If the detector code and classifier code disagree, show the disagreement warning. The final species recorded is the classifier’s top class.

Saving adds exactly one to the matching species counter in `weekly_surveillance` and `surveillance_records`:
- `AB` → `aedes_albopictus_count`
- `AG` → `aedes_aegypti_count`
- `CQ` → `culex_count`
- `AN` → `anopheles_count`

No generic Aedes aggregate is used, and no unknown bucket is recorded in the current app logic.

## Pages and UI

### Landing page
`lib/src/landing_page.dart` contains:
- the barangay selector,
- the scan action,
- the “Recent Captures” section.

The recent-captures section is backed by `SurveillanceRepository.getRecentRecords(limit: 5)`. It displays up to five newest rows sorted by `capture_timestamp DESC, id DESC`. Each row shows a thumbnail, species text, barangay, and timestamp. It loads on init and reloads after returning from the camera or records pages. Empty, loading, and error states are all handled in the widget.

“See all” switches to the Records tab through `AppNavigation`; it does not push a
second records route. Scanning is unchanged: selecting a barangay is required,
and the camera route is full-screen above the app shell.

### Records page
`lib/src/records_page.dart` is the Records tab and lists saved records and
weekly surveillance without a route-style back arrow. It reloads when selected
and when `recordsVersion` changes after a successful save. Each record row shows:
- a thumbnail (`RecordPhotoThumbnail`),
- species full name,
- date/time,
- barangay,
- a tap to open the shared detail page.

The records page shows the current weekly surveillance summary with the four per-species counters and a total-records count.

### Shared photo widgets
`lib/src/record_widgets.dart` holds the shared photo thumbnail and full-detail viewer used by both the landing page and the records page. That includes the safe placeholder for missing or unreadable files and the `InteractiveViewer` detail screen.

### Prediction page
The live Prediction tab is `AedesPredictionPage` in
`lib/src/prediction/aedes_prediction_page.dart`; `lib/src/app_shell.dart`
places it in the existing third `IndexedStack` tab. The legacy
`lib/src/prediction_page.dart` only re-exports this page. The old sample-data
module, demo scenarios, banner, and placeholder thresholds were removed.

The page uses `kOzamizBarangays` for its barangay selector. The Home page's
selected barangay is local to Home, not shared session state, so Prediction
maintains its own single-barangay selection. The query never combines
barangays. Because the shell keeps tabs alive, the page refreshes when tab 2 is
selected and when `AppNavigation.recordsVersion` changes after a record is
saved. Model/repository initialization is deferred until Prediction is first
selected.

For complete five-week data, the page displays P(Increase), Increase/Decrease,
the five ordered feature values, weekly positive/observed-day counts, and each
week's positivity. Any missing exact week displays “Insufficient data” rather
than treating missing observations as zero. The initial inactive state,
loading spinner, model/prediction errors, empty selected-barangay state, and
insufficient-data state are handled in the page. If the five-week window has no
processed records, `hasObservationsForBarangay()` selects the empty message;
some but incomplete weekly coverage displays “Insufficient data.”

The page warns that the selected barangay may not have been represented in
training data. Its disclaimer identifies the result as decision-support for
weekly *Aedes aegypti* positivity direction four weeks ahead—not a count,
population-density estimate, or outbreak forecast—and notes the prototype
training size, lack of retraining after new scans, and need to follow City
Health Office protocols.

### Profile page
`lib/src/profile_page.dart` is a real account page used behind the root auth
gate. It displays the current account, role/status, offline mode when active,
last online check, offline-access expiry, a status refresh action, and sign out.
Its About card uses `kAppVersion` from `lib/src/app_info.dart`; it also states
that scan records and photos remain on-device and location is not collected.

## Aedes direction prediction (logistic regression)

The offline model integration is in `lib/src/prediction/`:

- `aedes_logistic_predictor.dart` loads and validates the parameter asset,
  standardizes the five inputs, and calculates the logistic probability and
  class.
- `aedes_activity_repository.dart` aggregates local `surveillance_records`
  into weekly activity for one barangay and optionally stores prediction
  history.
- `aedes_prediction_page.dart` implements the live Prediction tab and refresh
  behavior.

`assets/aedes_model_parameters.json` contains the exported scaler means,
scales, logistic-regression coefficients, intercept, feature names, and class
labels. `pubspec.yaml` includes it as a Flutter asset. The required model input
order is `[Lag_1, Lag_2, Lag_3, Lag_4, Current_Activity]`; the predictor checks
this exact order, five means, five scales, five coefficients, nonzero positive
scales, a finite intercept, and class labels `0, 1` at runtime. Class `0` maps
to Decrease and class `1` maps to Increase.
`Lag_1` through `Lag_4` are the four preceding calendar-week values, with
`Lag_1` the most recent prior week; `Current_Activity` is the current week's
positivity.

For each input, standardization is `z_i = (x_i - mean_i) / scale_i`. The linear
score is `s = intercept + Σ(coefficient_i × z_i)`, and
`P(Increase) = 1 / (1 + exp(-s))`. The predicted class is Increase when
`P(Increase) >= 0.50`, otherwise Decrease; `P(Decrease) = 1 - P(Increase)`.

The activity repository uses ISO weeks beginning Monday. Weekly positivity is
`positive observed days / observed days`, for the selected barangay only. A
date is observed when at least one processed saved record for that barangay
exists on that date. A date is positive when at least one of its records has
`species_code = 'AG'`; multiple scans on one date count as one observed day.
Each of the current ISO week and its four exact preceding weeks must have at
least one observed day. If any week is missing, `predictForBarangay()` returns
`null`, which the page displays as “Insufficient data”; absent weeks/days are
never zero-filled.

All inference and data access are local; the prediction feature makes no
network calls. The model parameters are fixed and are not retrained when a new
scan is saved. After the Result page saves an observation it calls
`AppNavigation.notifyRecordsChanged()`. If Prediction is selected, the
`recordsVersion` change triggers a fresh aggregation and prediction, so a saved
record can change that barangay's daily/weekly positivity and next result.

## SQLite database

The current schema version is `3` (`AppDatabase.schemaVersion`), and the schema is created in `lib/src/data/app_database.dart`.

### Tables

#### `users`
Columns:
- `id INTEGER PRIMARY KEY AUTOINCREMENT`
- `username TEXT NOT NULL UNIQUE`
- `full_name TEXT NOT NULL`
- `role TEXT NOT NULL`
- `created_at TEXT NOT NULL`

Notes:
- The repository ensures a local Field Worker user exists.
- This is not a user-authentication flow.

#### `weekly_surveillance`
Columns:
- `id INTEGER PRIMARY KEY AUTOINCREMENT`
- `year INTEGER NOT NULL`
- `week_number INTEGER NOT NULL`
- `week_start TEXT NOT NULL`
- `week_end TEXT NOT NULL`
- `barangay TEXT NOT NULL`
- `aedes_albopictus_count INTEGER NOT NULL DEFAULT 0`
- `aedes_aegypti_count INTEGER NOT NULL DEFAULT 0`
- `culex_count INTEGER NOT NULL DEFAULT 0`
- `anopheles_count INTEGER NOT NULL DEFAULT 0`
- `updated_at TEXT NOT NULL`
- Unique key: `(year, week_number, barangay)`

This table is upserted by week and barangay, and aggregates counts per species.

#### `surveillance_sessions`
Columns:
- `id INTEGER PRIMARY KEY AUTOINCREMENT`
- `user_id INTEGER`
- `barangay TEXT`
- `started_at TEXT NOT NULL`
- `ended_at TEXT`
- `notes TEXT`
- Foreign key: `user_id -> users(id) ON DELETE SET NULL`

#### `surveillance_records`
Columns:
- `id INTEGER PRIMARY KEY AUTOINCREMENT`
- `session_id INTEGER NOT NULL`
- `week_id INTEGER`
- `image_path TEXT NOT NULL`
- `barangay TEXT NOT NULL`
- `capture_timestamp TEXT NOT NULL`
- `species_code TEXT NOT NULL`
- `aedes_albopictus_count INTEGER NOT NULL DEFAULT 0`
- `aedes_aegypti_count INTEGER NOT NULL DEFAULT 0`
- `culex_count INTEGER NOT NULL DEFAULT 0`
- `anopheles_count INTEGER NOT NULL DEFAULT 0`
- `total_detections INTEGER NOT NULL DEFAULT 0`
- `avg_confidence REAL`
- `processing_status TEXT NOT NULL DEFAULT 'processed'`
- `created_at TEXT NOT NULL`
- Foreign keys:
  - `session_id -> surveillance_sessions(id) ON DELETE CASCADE`
  - `week_id -> weekly_surveillance(id) ON DELETE SET NULL`

#### `prediction_results`
Columns:
- `id INTEGER PRIMARY KEY AUTOINCREMENT`
- `week_id INTEGER`
- `training_start TEXT`
- `training_end TEXT`
- `latest_observed INTEGER NOT NULL`
- `predicted_count REAL NOT NULL`
- `predicted_change REAL NOT NULL`
- `increase_likely INTEGER NOT NULL`
- `created_at TEXT NOT NULL`
- Foreign key: `week_id -> weekly_surveillance(id) ON DELETE SET NULL`

This is the pre-existing prediction table. The on-device Aedes feature does not
read or write it; `SurveillanceRepository.savePrediction()` and
`SurveillanceRepository.latestPrediction()` remain available for the legacy
table and are not called by the live Prediction tab.

#### `aedes_direction_predictions`
Columns:
- `id INTEGER PRIMARY KEY AUTOINCREMENT`
- `barangay TEXT NOT NULL`
- `current_week_start TEXT NOT NULL`
- `lag_1 REAL NOT NULL`
- `lag_2 REAL NOT NULL`
- `lag_3 REAL NOT NULL`
- `lag_4 REAL NOT NULL`
- `current_activity REAL NOT NULL`
- `probability_increase REAL NOT NULL`
- `probability_decrease REAL NOT NULL`
- `predicted_class INTEGER NOT NULL`
- `model_version TEXT NOT NULL`
- `created_at TEXT NOT NULL`

`AedesActivityRepository.ensurePredictionTable()` creates this table with
`CREATE TABLE IF NOT EXISTS` and creates its barangay/week index. Both
`predictForBarangay()` and `predictionHistory()` call the ensure method, so the
table is created on first repository use even when the database already exists
at schema version 3. `AppDatabase.schemaVersion` remains `3`; the existing
tables and their columns were not altered.
The existing-version-3 first-use case is covered by
`test/aedes_activity_repository_test.dart`.

## Data model and repository patterns

The repository is `lib/src/data/surveillance_repository.dart`.

It currently supports:
- `saveObservation(...)` for saving a scanned larva
- `getRecentRecords({limit = 5})` for the landing page
- `recentRecords({limit = 100})` for the records page
- `weeklySeries()` for weekly totals
- `recordCount()`
- `latestWeek()` and `latestPrediction()`
- `savePrediction()`

The separate `lib/src/prediction/aedes_activity_repository.dart` exposes:

- `ensurePredictionTable()`: create the prediction-history table and index if
  missing.
- `hasObservationsForBarangay(String barangay, {DateTime? referenceDate})`:
  check whether the selected barangay has processed records in the exact
  five-week prediction window.
- `predictForBarangay(String barangay, {DateTime? referenceDate, bool saveResult = true})`:
  aggregate the selected barangay's five exact ISO weeks, infer a direction,
  and optionally persist the result.
- `predictionHistory(String barangay)`: return the newest 30 saved predictions
  for that barangay.

The live prediction feature uses `aedes_direction_predictions`, not
`prediction_results`. The old `savePrediction()` and `latestPrediction()` APIs
are exercised by legacy repository tests but have no live UI call sites.

The repository writes the saved photo under the app documents directory in `wayawaya/records`, and stores that file path in `surveillance_records.image_path`.

The photo-saved file naming pattern is:
- `yyyyMMdd_HHmmss_<speciesCode>.jpg`

Example:
- `20261025_143012_AG.jpg`

The storage code decodes the photo, bakes EXIF orientation, resizes the long side to a maximum of 1280 px while preserving aspect ratio, and writes JPEG quality 90. If re-encoding fails, it falls back to saving the original bytes and logs the failure.

## Important current realities

- No geolocation or location permission code remains in the app.
- `lib/src/constants.dart` defines the 51-item barangay list. Home's selected
  barangay is widget-local; Prediction keeps its own selected barangay.
- The landing page shows all barangays in the recent-captures list because it queries all saved records, with the barangay given in each row.
- The app is intentionally save-on-user-tap: no record is inserted until the user confirms Save on the result page.
- The database is versioned at `schemaVersion = 3`.
- The migration from older schema versions removes old record image files
  before recreating the existing surveillance and `prediction_results` tables.
- The logistic-regression model is preliminary and runs offline using fixed
  exported parameters; newly saved observations affect inputs, not training.

## Authentication and profile

- `lib/src/auth/` contains the API client, secure storage adapter, PBKDF2 password
  hashing, authentication controller, messages, and auth screens.
- The app uses a root auth gate: splash during bootstrap, Login or registration
  screens when signed out, and the four-tab AppShell when signed in.
- Successful e-mail verification may return `already_verified` and is treated as
  verification success. The verify screen disables its code field and verify
  button while one request is running, maps inline error codes, and clears its
  in-memory registration password before automatic sign-in.
- After verification, the app shows a non-dismissible Account Created screen.
  It holds the root auth gate in that state after a successful session login,
  until "Start scanning" or "Go to login" is pressed.
- The server contract is defined in `auth_api.dart`. Successful responses are
  parsed as API envelopes; network failures are distinct from server answers.
- One account is stored per device in secure storage. Stored auth values include
  token, user JSON, token expiry, e-mail, PBKDF2 salt/hash/iteration count, last
  online verification time, maximum observed device time, failed offline attempts,
  and lockout expiry.
- Online login stores a random-salt PBKDF2-HMAC-SHA256 password hash at 150,000
  iterations. The plain password is not persisted and is discarded after
  verification or login.
- Offline login is allowed only for the matching local account within 30 days of
  the last server verification and only if the device clock was not moved back
  more than five minutes. Wrong passwords follow persisted 30-second, 1-minute,
  5-minute, and 15-minute lockouts after every fifth consecutive failure.
- Bootstrap shows the AppShell immediately when an offline-valid session exists,
  then checks `/api/me.php` in the background. Logout revokes the server token
  when reachable and always clears the auth secure-storage values. Scan records,
  photos, and the local SQLite schema remain independent.

## Limitations

- The preliminary model was trained on 92 eligible rows from 13 barangays.
- Only `AG` (Aedes aegypti) counts as a positive day. Any processed non-`AG`
  record without an `AG` record on that date counts as a negative observed day;
  City Health must confirm this daily rule before operational use.
- The output predicts the direction of weekly positivity four weeks ahead. It
  does not predict larval counts, mosquito population density, or outbreaks.
- The 0.50 classification cutoff is the default classifier boundary, not a
  validated public-health action threshold.
- Model performance is unvalidated for barangays absent from the training
  data; the page shows a limited-evidence notice because the parameter asset
  has no barangay-specific representation metadata.
- Python-versus-Dart `predict_proba` parity for
  `[0.5, 0.6, 0.7, 0.4, 0.55]` is pending. The predictor test contains a
  clearly marked TODO to compare within `1e-6` when the Python output is
  provided.

## Testing

Prediction-focused tests:

- `test/aedes_logistic_predictor_test.dart`: load the checked-in parameters;
  verify feature order, vector dimensions, class labels, and input bounds.
  Python parity remains marked TODO.
- `test/aedes_activity_repository_test.dart`: use temporary FFI SQLite
  databases to verify complete and missing five-week histories, barangay
  isolation, same-day deduplication, positive/negative day rules, and first-use
  table creation against a version-3 database.
- `test/prediction_page_test.dart`: verify the 51-item selector, displayed
  prediction outputs/disclaimers, insufficient data, and refreshes on tab
  selection and `recordsVersion`.
- `test/app_shell_test.dart`: verify tab order, icon-only navigation, back
  behavior, and existing Records refresh behavior with the Prediction tab in
  the shell.

Other tests under `test/` cover authentication, database migrations and
repositories, saved photos, preprocessing, detection/classification, and
screen behavior. Run the full suite with:

```shell
flutter test
```
