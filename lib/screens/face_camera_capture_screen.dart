import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class FaceCameraCaptureScreen extends StatefulWidget {
  const FaceCameraCaptureScreen({super.key});

  @override
  State<FaceCameraCaptureScreen> createState() => _FaceCameraCaptureScreenState();
}

class _FaceCameraCaptureScreenState extends State<FaceCameraCaptureScreen> {
  static const MethodChannel _windowsCameraExtChannel =
      MethodChannel('flutter_cam/camera_windows_ext');
  static const List<String> _requiredPoses = <String>[
    'Chinh dien',
    'Nghieng trai',
    'Nghieng phai',
    'Ngua len tren',
    'Cuoi xuong duoi',
  ];

  CameraController? _controller;
  bool _loading = true;
  bool _capturing = false;
  String? _error;
  final List<Uint8List> _capturedImages = <Uint8List>[];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      var cameras = await availableCameras();
      if (cameras.isEmpty) {
        // Camera backend can need a short settling time right after another
        // controller releases the device.
        await Future<void>.delayed(const Duration(milliseconds: 350));
        cameras = await availableCameras();
      }
      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Khong tim thay camera.';
        });
        return;
      }

      final controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: _preferredImageFormat(),
      );
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Khong mo duoc camera: $e';
      });
    }
  }

  ImageFormatGroup _preferredImageFormat() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.iOS:
        return ImageFormatGroup.bgra8888;
      case TargetPlatform.android:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return ImageFormatGroup.yuv420;
    }
  }

  Future<Uint8List> _captureFrame() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw StateError('Camera chua san sang.');
    }

    if (!controller.supportsImageStreaming()) {
      return _captureWithoutStream(controller);
    }

    final completer = Completer<Uint8List>();
    var captured = false;
    await controller.startImageStream((image) {
      if (captured) return;
      captured = true;
      unawaited(_completeCaptureFromFrame(controller, image, completer));
    });

    final bytes = await completer.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        throw TimeoutException('Khong lay duoc frame tu stream.');
      },
    );

    return bytes;
  }

  Future<Uint8List> _captureWithoutStream(CameraController controller) async {
    final fromWindowsPreview = await _capturePreviewFrameFromWindows(controller);
    if (fromWindowsPreview != null) {
      return fromWindowsPreview;
    }

    final shot = await controller.takePicture();
    return shot.readAsBytes();
  }

  Future<Uint8List?> _capturePreviewFrameFromWindows(
    CameraController controller,
  ) async {
    if (!Platform.isWindows) {
      return null;
    }

    final int cameraId = controller.cameraId;
    final Object? response = await _windowsCameraExtChannel.invokeMethod<Object?>(
      'getLatestFrameBgra',
      <String, Object?>{'cameraId': cameraId},
    );
    if (response is! Map<Object?, Object?>) {
      return null;
    }

    final Object? bytesRaw = response['bytes'];
    final Object? widthRaw = response['width'];
    final Object? heightRaw = response['height'];
    if (bytesRaw == null || widthRaw == null || heightRaw == null) {
      return null;
    }

    final int width = (widthRaw as num).toInt();
    final int height = (heightRaw as num).toInt();
    if (width <= 0 || height <= 0) {
      return null;
    }

    final Uint8List bytes = bytesRaw is Uint8List
        ? bytesRaw
        : Uint8List.fromList((bytesRaw as List<Object?>).cast<int>());
    if (bytes.length < width * height * 4) {
      return null;
    }

    final decoded = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: bytes.buffer,
      format: img.Format.uint8,
      order: img.ChannelOrder.bgra,
      numChannels: 4,
    );

    return Uint8List.fromList(img.encodeJpg(decoded, quality: 92));
  }

  Future<void> _capturePose() async {
    if (_capturing || _capturedImages.length >= _requiredPoses.length) {
      return;
    }

    setState(() {
      _capturing = true;
      _error = null;
    });

    try {
      final bytes = await _captureFrame();
      if (!mounted) return;
      setState(() {
        _capturedImages.add(bytes);
      });

      if (_capturedImages.length == _requiredPoses.length) {
        Navigator.of(context).pop<List<Uint8List>>(
          List<Uint8List>.from(_capturedImages),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Chup that bai: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _capturing = false;
        });
      }
    }
  }

  void _retakeCurrentStep() {
    if (_capturing || _capturedImages.isEmpty) return;
    setState(() {
      _capturedImages.removeLast();
      _error = null;
    });
  }

  Future<void> _completeCaptureFromFrame(
    CameraController controller,
    CameraImage image,
    Completer<Uint8List> completer,
  ) async {
    try {
      final rgb = _cameraImageToRgb(image);
      if (rgb == null) {
        throw StateError('Khong chuyen doi duoc frame camera.');
      }
      final jpg = img.encodeJpg(rgb, quality: 92);
      if (!completer.isCompleted) {
        completer.complete(Uint8List.fromList(jpg));
      }
    } catch (e) {
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    } finally {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    }
  }

  img.Image? _cameraImageToRgb(CameraImage image) {
    if (image.planes.isEmpty) return null;
    if (image.format.group == ImageFormatGroup.bgra8888) {
      final bytes = image.planes.first.bytes;
      return img.Image.fromBytes(
        width: image.width,
        height: image.height,
        bytes: bytes.buffer,
        format: img.Format.uint8,
        order: img.ChannelOrder.bgra,
        numChannels: 4,
      );
    }

    if (image.format.group == ImageFormatGroup.yuv420 && image.planes.length >= 3) {
      final width = image.width;
      final height = image.height;
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];
      final out = img.Image(width: width, height: height);

      for (var y = 0; y < height; y++) {
        final uvRow = y >> 1;
        for (var x = 0; x < width; x++) {
          final uvCol = x >> 1;
          final yi = y * yPlane.bytesPerRow + x;
          final ui = uvRow * uPlane.bytesPerRow + uvCol * uPlane.bytesPerPixel!;
          final vi = uvRow * vPlane.bytesPerRow + uvCol * vPlane.bytesPerPixel!;

          final yValue = yPlane.bytes[yi];
          final uValue = uPlane.bytes[ui];
          final vValue = vPlane.bytes[vi];

          final c = yValue - 16;
          final d = uValue - 128;
          final e = vValue - 128;
          final r = ((298 * c + 409 * e + 128) >> 8).clamp(0, 255);
          final g = ((298 * c - 100 * d - 208 * e + 128) >> 8).clamp(0, 255);
          final b = ((298 * c + 516 * d + 128) >> 8).clamp(0, 255);

          out.setPixelRgb(x, y, r, g, b);
        }
      }
      return out;
    }

    return null;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentStep = _capturedImages.length;
    final completed = currentStep >= _requiredPoses.length;
    final currentPose = completed ? _requiredPoses.last : _requiredPoses[currentStep];

    return Scaffold(
      appBar: AppBar(title: const Text('Chup 5 goc khuon mat')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _controller == null
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Buoc ${currentStep + 1}/5: $currentPose',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Chup du 5 vi tri: chinh dien, trai, phai, tren, duoi.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: CameraPreview(_controller!),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Row(
                        children: List<Widget>.generate(_requiredPoses.length, (index) {
                          final done = index < _capturedImages.length;
                          return Expanded(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: done
                                    ? Theme.of(context).colorScheme.primaryContainer
                                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                done ? Icons.check_circle : Icons.radio_button_unchecked,
                                size: 18,
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _capturedImages.isEmpty ? null : _retakeCurrentStep,
                              icon: const Icon(Icons.undo),
                              label: const Text('Chup lai buoc'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _capturing || completed ? null : _capturePose,
                              icon: _capturing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.camera_alt),
                              label: Text(completed ? 'Da du 5 anh' : 'Chup buoc tiep'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: Text(
                          _error!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                  ],
                ),
    );
  }
}
