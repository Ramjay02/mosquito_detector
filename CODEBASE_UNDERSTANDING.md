# Waya-waya Scanner Codebase Guide

## Overview and app flow

Waya-waya Scanner is a Flutter app that detects and classifies mosquito larvae in phone photos taken with a clip-on microscope lens. The package name remains `mosquito_detector`, and the visible app name is `Waya-waya Scanner`.

`main.dart` creates a dark Material 3 `MaterialApp` whose home is
`lib/src/app_shell.dart`. The shell uses an `IndexedStack` to keep four tabs
alive in this order: Home, Records, Prediction, and Profile. Its icon-only
Material 3 `NavigationBar` stays visible at the bottom of tab pages and respects
the system gesture area. Selecting a tab changes the stack index without
recreating the other tab states.

`lib/src/app_navigation.dart` contains the small, resettable navigation state:
`selectedTab` chooses the current tab and `recordsVersion` notifies the Records
tab that saved records changed. Back on a non-Home tab returns to Home; Home
allows the normal route/app back behavior. Camera, result, and record-detail
screens are pushed above the shell, so they cover the bottom bar.

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
5. Prediction and Profile: static sample/demo pages; prediction is not
   connected to a model.

Location collection, permissions, and geolocation code have been removed. There is no `location_service.dart`, no geolocator dependency, and no location fields anywhere in the current UI or database schema.

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

### Prediction page (static sample)
`lib/src/prediction_page.dart` is a static, local-only UI preview about the
weekly presence of *Aedes aegypti* in a selected barangay and the direction of
change four weeks ahead. It does not call the database, a model, or a network
service. A permanent sample-data banner explains that the prediction model is
not connected and that final decisions belong to trained health personnel.

`lib/src/data/prediction_sample.dart` defines the UI-facing sample types:

- `WeekObservation`: week label, positive days, observed days, and `presence`.
  `presence` is null when `observedDays` is zero.
- `AedesOutlook`: barangay, current week, four previous weeks, probability of
  increase, limited-evidence flag, and missing-week labels.
- Four fixed preview scenarios (`S1`–`S4`) demonstrate likely increase, likely
  decrease, uncertain, and insufficient-data states.
- `likelyIncreaseMin` (0.60), `likelyDecreaseMax` (0.40), and
  `highPresenceMin` (0.50) are explicitly placeholder thresholds, not
  validated.

The page describes presence as the share of observed days with *Aedes aegypti*
found, not a larva count. It presents current presence, the four-week direction
outlook, inputs, a five-week widget chart, suggested actions, and explanatory
copy. Empty observed weeks display “No data,” never a fabricated 0% presence.
The sample probabilities and UI do not represent an operational prediction
model.

### Profile page (static sample)
`lib/src/profile_page.dart` is a static profile preview; authentication and
accounts are not implemented. It shows a sample profile and “Not signed in -
accounts are coming soon” banner. Sign in and Register are disabled and marked
“Coming soon.” The About card uses `kAppVersion` from
`lib/src/app_info.dart`. Its privacy note states that scan records and photos
are stored on-device and location is not collected.

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

The repository writes the saved photo under the app documents directory in `wayawaya/records`, and stores that file path in `surveillance_records.image_path`.

The photo-saved file naming pattern is:
- `yyyyMMdd_HHmmss_<speciesCode>.jpg`

Example:
- `20261025_143012_AG.jpg`

The storage code decodes the photo, bakes EXIF orientation, resizes the long side to a maximum of 1280 px while preserving aspect ratio, and writes JPEG quality 90. If re-encoding fails, it falls back to saving the original bytes and logs the failure.

## Important current realities

- No geolocation or location permission code remains in the app.
- `lib/src/constants.dart` defines the exact barangay list and keeps the selected barangay in session state.
- The landing page shows all barangays in the recent-captures list because it queries all saved records, with the barangay given in each row.
- The app is intentionally save-on-user-tap: no record is inserted until the user confirms Save on the result page.
- The database is versioned at `schemaVersion = 3`.
- The migration from older schema versions removes old record image files before recreating the surveillance and prediction tables.

## Authentication and profile

- `lib/src/auth/` contains the API client, secure storage adapter, PBKDF2 password
  hashing, authentication controller, messages, and auth screens.
- The app uses a root auth gate: splash during bootstrap, Login or registration
  screens when signed out, the four-tab AppShell when signed in, and an
  approval screen for pending accounts.
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
