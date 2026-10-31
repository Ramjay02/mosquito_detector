import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'constants.dart';
import 'data/surveillance_repository.dart';
import 'inference_engine.dart';
import 'preprocess.dart';
import 'result_page.dart';
import 'yolo_decoder.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key, required this.barangay});

  final String barangay;

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  final InferenceEngine _engine = InferenceEngine();
  final SurveillanceRepository _repository = SurveillanceRepository();

  CameraController? _controller;
  bool _busy = false;
  bool _loadingModels = true;
  String? _error;
  bool _initializingCamera = false;
  int? _userId;

  double _zoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _scaleBase = 1.0;
  Offset? _focusPos;
  int _focusToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _engine.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final CameraController? controller = _controller;
      _controller = null;
      controller?.dispose();
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _init() async {
    try {
      _userId = await _repository.ensureLocalUser();
    } catch (e) {
      debugPrint('database init failed: $e');
    }
    await _engine.load();
    if (!mounted) {
      return;
    }
    if (!_engine.ready) {
      setState(() {
        _loadingModels = false;
        _error = _engine.loadError;
      });
      return;
    }
    setState(() => _loadingModels = false);

    await _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (_initializingCamera || !mounted) {
      return;
    }
    _initializingCamera = true;
    try {
      final List<CameraDescription> cameras = await availableCameras();
      if (!mounted || cameras.isEmpty) {
        return;
      }
      final CameraDescription back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final CameraController controller = CameraController(
        back,
        ResolutionPreset.veryHigh,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      try {
        _minZoom = await controller.getMinZoomLevel();
        _maxZoom = await controller.getMaxZoomLevel();
        _zoom = _minZoom;
        _scaleBase = _minZoom;
      } catch (_) {
        _minZoom = 1.0;
        _maxZoom = 1.0;
        _zoom = 1.0;
      }
      final CameraController? previous = _controller;
      setState(() {
        _error = null;
        _controller = controller;
      });
      await previous?.dispose();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Camera failed: $e');
      }
    } finally {
      _initializingCamera = false;
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _scaleBase = _zoom;
  }

  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final double target = (_scaleBase * details.scale).clamp(
      _minZoom,
      _maxZoom,
    );
    if ((target - _zoom).abs() < 0.01) {
      return;
    }
    setState(() => _zoom = target);
    try {
      await controller.setZoomLevel(target);
    } catch (_) {}
  }

  Future<void> _applyZoom(double target) async {
    final double clamped = target.clamp(_minZoom, _maxZoom);
    setState(() => _zoom = clamped);
    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    try {
      await controller.setZoomLevel(clamped);
    } catch (_) {}
  }

  void _toggleZoom() {
    final double mid = ((_minZoom + _maxZoom) / 2).clamp(_minZoom, _maxZoom);
    final double target = (_zoom > _minZoom + 0.5) ? _minZoom : mid;
    _applyZoom(target);
  }

  Future<void> _onTapFocus(TapDownDetails details, Size box) async {
    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final Offset normalized = Offset(
      (details.localPosition.dx / box.width).clamp(0.0, 1.0),
      (details.localPosition.dy / box.height).clamp(0.0, 1.0),
    );
    final int token = ++_focusToken;
    setState(() => _focusPos = normalized);
    try {
      await controller.setFocusPoint(normalized);
      await controller.setExposurePoint(normalized);
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted && _focusToken == token) {
      setState(() => _focusPos = null);
    }
  }

  Future<void> _capture() async {
    final CameraController? controller = _controller;
    if (_busy || controller == null || !controller.value.isInitialized) {
      return;
    }
    if (controller.value.isTakingPicture) {
      return;
    }
    if (!_engine.ready) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_engine.loadError ?? 'Models are not ready.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final XFile photo = await controller.takePicture();
      await _analyze(await photo.readAsBytes());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Capture failed: $e\n'
              'state=${_controller?.value}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (_busy) {
      return;
    }
    final XFile? picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    if (picked == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _analyze(await picked.readAsBytes());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Analysis failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _analyze(Uint8List bytes) async {
    if (!_engine.ready) {
      throw StateError(_engine.loadError ?? 'Models are not ready.');
    }
    final DateTime capturedAt = DateTime.now();
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('decodeImage failed');
    }
    final img.Image oriented = img.bakeOrientation(decoded);
    final Processed640 frame = await _engine.preprocessInIsolate(bytes);
    if (kDebugMode) {
      debugPrint('FOCUS_SCORE:${frame.focusScore}');
    }
    if (kFocusThreshold > 0 && frame.focusScore < kFocusThreshold) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image looks blurry - hold steady and retake'),
          ),
        );
      }
      return;
    }
    final List<Detection> detections = _engine.detect(frame);
    debugPrint('detections: ${detections.length}');
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ResultPage(
          engine: _engine,
          repository: _repository,
          jpeg: bytes,
          oriented: oriented,
          processedFrame: frame,
          detections: detections,
          capturedAt: capturedAt,
          barangay: widget.barangay,
          userId: _userId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? error = _error;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Waya-waya Scanner',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _buildPreview(error)),
          if (!_loadingModels && !_engine.detectorLoaded)
            Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: Card(
                color: Colors.orange.shade900,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    'Detector model missing. Details:\n${_engine.loadError}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 56,
                      height: 56,
                      child: IconButton.filledTonal(
                        onPressed: _busy ? null : _pickFromGallery,
                        tooltip: 'Analyze from gallery',
                        icon: const Icon(Icons.photo_library_outlined),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 96,
                      height: 96,
                      child: _busy
                          ? const Padding(
                              padding: EdgeInsets.all(20),
                              child: CircularProgressIndicator(),
                            )
                          : FloatingActionButton.large(
                              onPressed: _capture,
                              child: const Icon(Icons.camera_alt),
                            ),
                    ),
                    const SizedBox(width: 16),
                    const SizedBox(width: 56, height: 56),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(String? error) {
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(error, textAlign: TextAlign.center),
        ),
      );
    }
    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    final bool canZoom = _maxZoom - _minZoom > 0.01;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        Center(
          child: CameraPreview(
            controller,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final Size box = constraints.biggest;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _onTapFocus(d, box),
                  onScaleStart: _handleScaleStart,
                  onScaleUpdate: _handleScaleUpdate,
                  onDoubleTap: _toggleZoom,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_focusPos != null)
                        _FocusReticle(
                          key: ValueKey<int>(_focusToken),
                          normalized: _focusPos!,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        if (canZoom)
          Positioned(
            left: 48,
            right: 48,
            bottom: 150,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_zoom.toStringAsFixed(1)}x',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                Slider(
                  value: _zoom.clamp(_minZoom, _maxZoom),
                  min: _minZoom,
                  max: _maxZoom,
                  onChanged: _applyZoom,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FocusReticle extends StatelessWidget {
  const _FocusReticle({super.key, required this.normalized});

  final Offset normalized;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment(normalized.dx * 2 - 1, normalized.dy * 2 - 1),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 1.6, end: 1.0),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF00E5FF), width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}
