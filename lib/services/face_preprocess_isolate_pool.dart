import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class FacePreprocessResult {
  FacePreprocessResult({
    required this.processedJpeg,
    required this.frameQuality,
    required this.luminance,
    required this.sharpnessQuality,
  });

  final Uint8List processedJpeg;
  final double frameQuality;
  final double luminance;
  final double sharpnessQuality;
}

class FacePreprocessIsolatePool {
  final List<_PreprocessWorker> _workers = <_PreprocessWorker>[];
  int _rrIndex = 0;

  bool get isReady => _workers.isNotEmpty;

  Future<void> start({required int workerCount}) async {
    await dispose();
    final safeCount = workerCount.clamp(1, 8);
    for (var i = 0; i < safeCount; i++) {
      _workers.add(await _PreprocessWorker.spawn());
    }
  }

  Future<void> dispose() async {
    for (final worker in _workers) {
      await worker.dispose();
    }
    _workers.clear();
    _rrIndex = 0;
  }

  Future<FacePreprocessResult?> preprocessCrop({
    required Uint8List cropPng,
    required double minSharpness,
    required bool enableAutoSharpen,
    required double maxSharpenAmount,
  }) async {
    if (_workers.isEmpty) return null;
    final worker = _workers[_rrIndex % _workers.length];
    _rrIndex = (_rrIndex + 1) % _workers.length;
    return worker.process(
      cropPng: cropPng,
      minSharpness: minSharpness,
      enableAutoSharpen: enableAutoSharpen,
      maxSharpenAmount: maxSharpenAmount,
    );
  }

  Future<List<double>?> computeFallbackVector({required Uint8List cropPng}) {
    if (_workers.isEmpty) {
      return Future<List<double>?>.value(null);
    }
    final worker = _workers[_rrIndex % _workers.length];
    _rrIndex = (_rrIndex + 1) % _workers.length;
    return worker.computeFallbackVector(cropPng: cropPng);
  }
}

class _PreprocessWorker {
  _PreprocessWorker({
    required this.isolate,
    required this.commandPort,
    required this.responsePort,
  }) {
    _sub = responsePort.listen(_onMessage);
  }

  final Isolate isolate;
  final SendPort commandPort;
  final ReceivePort responsePort;
  late final StreamSubscription<dynamic> _sub;
  int _nextId = 1;
    final Map<int, Completer<FacePreprocessResult?>> _pendingPreprocess =
      <int, Completer<FacePreprocessResult?>>{};
    final Map<int, Completer<List<double>?>> _pendingVector =
      <int, Completer<List<double>?>>{};

  static Future<_PreprocessWorker> spawn() async {
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(_workerMain, receivePort.sendPort);
    final first = await receivePort.first;
    if (first is! SendPort) {
      receivePort.close();
      isolate.kill(priority: Isolate.immediate);
      throw StateError('Preprocess worker failed to initialize');
    }
    return _PreprocessWorker(
      isolate: isolate,
      commandPort: first,
      responsePort: receivePort,
    );
  }

  Future<FacePreprocessResult?> process({
    required Uint8List cropPng,
    required double minSharpness,
    required bool enableAutoSharpen,
    required double maxSharpenAmount,
  }) {
    final id = _nextId++;
    final completer = Completer<FacePreprocessResult?>();
    _pendingPreprocess[id] = completer;
    commandPort.send(<String, Object?>{
      'task': 'preprocess',
      'id': id,
      'crop': TransferableTypedData.fromList(<Uint8List>[cropPng]),
      'minSharpness': minSharpness,
      'enableAutoSharpen': enableAutoSharpen,
      'maxSharpenAmount': maxSharpenAmount,
    });
    return completer.future;
  }

  Future<List<double>?> computeFallbackVector({required Uint8List cropPng}) {
    final id = _nextId++;
    final completer = Completer<List<double>?>();
    _pendingVector[id] = completer;
    commandPort.send(<String, Object?>{
      'task': 'fallbackVector',
      'id': id,
      'crop': TransferableTypedData.fromList(<Uint8List>[cropPng]),
    });
    return completer.future;
  }

  Future<void> dispose() async {
    commandPort.send(const <String, Object?>{'cmd': 'dispose'});
    await _sub.cancel();
    responsePort.close();
    isolate.kill(priority: Isolate.immediate);
    for (final pending in _pendingPreprocess.values) {
      if (!pending.isCompleted) pending.complete(null);
    }
    for (final pending in _pendingVector.values) {
      if (!pending.isCompleted) pending.complete(null);
    }
    _pendingPreprocess.clear();
    _pendingVector.clear();
  }

  void _onMessage(dynamic message) {
    if (message is! Map) return;
    final id = message['id'];
    if (id is! int) return;
    final vectorCompleter = _pendingVector.remove(id);
    if (vectorCompleter != null) {
      final ok = message['ok'] == true;
      if (!ok || vectorCompleter.isCompleted) {
        vectorCompleter.complete(null);
        return;
      }
      final rawVector = message['vector'];
      if (rawVector is List) {
        final vector = rawVector
            .whereType<num>()
            .map((value) => value.toDouble())
            .toList(growable: false);
        vectorCompleter.complete(vector);
      } else {
        vectorCompleter.complete(null);
      }
      return;
    }

    final completer = _pendingPreprocess.remove(id);
    if (completer == null || completer.isCompleted) return;

    final ok = message['ok'] == true;
    if (!ok) {
      completer.complete(null);
      return;
    }

    final ttd = message['processed'];
    if (ttd is! TransferableTypedData) {
      completer.complete(null);
      return;
    }

    final bytes = ttd.materialize().asUint8List();
    final frameQuality = (message['frameQuality'] as num?)?.toDouble() ?? 0.0;
    final luminance = (message['luminance'] as num?)?.toDouble() ?? 0.0;
    final sharpnessQuality =
        (message['sharpnessQuality'] as num?)?.toDouble() ?? 0.0;
    completer.complete(
      FacePreprocessResult(
        processedJpeg: bytes,
        frameQuality: frameQuality,
        luminance: luminance,
        sharpnessQuality: sharpnessQuality,
      ),
    );
  }
}

void _workerMain(SendPort parentPort) {
  final commandPort = ReceivePort();
  parentPort.send(commandPort.sendPort);

  commandPort.listen((dynamic message) {
    if (message is! Map) return;
    if (message['cmd'] == 'dispose') {
      commandPort.close();
      return;
    }

    final id = message['id'];
    if (id is! int) return;
    try {
      final cropTtd = message['crop'];
      if (cropTtd is! TransferableTypedData) {
        parentPort.send(<String, Object?>{'id': id, 'ok': false});
        return;
      }

      final cropBytes = cropTtd.materialize().asUint8List();
        final task = (message['task'] as String?) ?? 'preprocess';
      final minSharpness =
          (message['minSharpness'] as num?)?.toDouble() ?? 20.0;
      final enableAutoSharpen = message['enableAutoSharpen'] == true;
      final maxSharpenAmount =
          ((message['maxSharpenAmount'] as num?)?.toDouble() ?? 1.0)
              .clamp(0.0, 1.0)
              .toDouble();

      final decoded = img.decodeImage(cropBytes);
      if (decoded == null) {
        parentPort.send(<String, Object?>{'id': id, 'ok': false});
        return;
      }

      if (task == 'fallbackVector') {
        final vector = _vectorFromImage(decoded);
        parentPort.send(<String, Object?>{
          'id': id,
          'ok': true,
          'vector': vector,
        });
        return;
      }

      var working = img.grayscale(decoded);
      var luminance = _robustFaceLuminance(working);
      final preSharpnessQuality = (_imageSharpness(working) / 140.0)
          .clamp(0.0, 1.0)
          .toDouble();
      final preLumaStdDev = _lumaStdDev(working, luminance);
      final autoSharpen = enableAutoSharpen
          ? _computeAutoSharpenAmount(
              sharpnessQuality: preSharpnessQuality,
              lumaStdDev: preLumaStdDev,
              maxSharpenAmount: maxSharpenAmount,
            )
          : 0.0;

      if (autoSharpen > 0.01) {
        working = _sharpenFaceCrop(working, autoSharpen);
      }

      luminance = _robustFaceLuminance(working);
      final sharpnessQuality = (_imageSharpness(working) / 140.0)
          .clamp(0.0, 1.0)
          .toDouble();
      final regionQuality = _regionQuality(working, minSharpness: minSharpness);
      final frameQuality = math
          .min(sharpnessQuality, regionQuality)
          .clamp(0.0, 1.0)
          .toDouble();

      // Use lossless encoding to avoid embedding drift from JPEG artifacts.
      final processed = Uint8List.fromList(img.encodePng(working));
      parentPort.send(<String, Object?>{
        'id': id,
        'ok': true,
        'processed': TransferableTypedData.fromList(<Uint8List>[processed]),
        'frameQuality': frameQuality,
        'luminance': luminance,
        'sharpnessQuality': sharpnessQuality,
      });
    } catch (_) {
      parentPort.send(<String, Object?>{'id': id, 'ok': false});
    }
  });
}

List<double> _vectorFromImage(img.Image source) {
  final square = _centerCropSquare(source);
  final resized = img.copyResize(
    square,
    width: 24,
    height: 24,
    interpolation: img.Interpolation.linear,
  );
  final rgb = resized.getBytes(order: img.ChannelOrder.rgb);
  final vector = List<double>.filled(24 * 24, 0.0);

  var sumSq = 0.0;
  var j = 0;
  for (var i = 0; i < rgb.length; i += 3) {
    final gray =
        (0.299 * rgb[i] + 0.587 * rgb[i + 1] + 0.114 * rgb[i + 2]) / 255.0;
    vector[j] = gray;
    sumSq += gray * gray;
    j++;
  }

  final norm = math.sqrt(sumSq);
  if (norm > 0) {
    for (var i = 0; i < vector.length; i++) {
      vector[i] = vector[i] / norm;
    }
  }
  return vector;
}

img.Image _centerCropSquare(img.Image input) {
  final side = math.min(input.width, input.height);
  final x = ((input.width - side) / 2).round();
  final y = ((input.height - side) / 2).round();
  return img.copyCrop(input, x: x, y: y, width: side, height: side);
}

double _imageSharpness(img.Image image) {
  final gray = img.grayscale(image);
  final width = gray.width;
  final height = gray.height;
  if (width < 3 || height < 3) return 0.0;

  final values = List<double>.filled((width - 2) * (height - 2), 0.0);
  var index = 0;
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final c = gray.getPixel(x, y).r.toDouble();
      final l = gray.getPixel(x - 1, y).r.toDouble();
      final r = gray.getPixel(x + 1, y).r.toDouble();
      final t = gray.getPixel(x, y - 1).r.toDouble();
      final b = gray.getPixel(x, y + 1).r.toDouble();
      values[index++] = (4 * c - l - r - t - b);
    }
  }

  if (values.isEmpty) return 0.0;
  var mean = 0.0;
  for (final v in values) {
    mean += v;
  }
  mean /= values.length;

  var variance = 0.0;
  for (final v in values) {
    final d = v - mean;
    variance += d * d;
  }
  variance /= values.length;
  return variance;
}

double _robustFaceLuminance(img.Image image) {
  final width = image.width;
  final height = image.height;
  if (width <= 0 || height <= 0) return 0.0;

  final left = (width * 0.15).floor().clamp(0, width - 1);
  final top = (height * 0.15).floor().clamp(0, height - 1);
  final right = (width * 0.85).ceil().clamp(left + 1, width);
  final bottom = (height * 0.85).ceil().clamp(top + 1, height);

  final histogram = List<int>.filled(256, 0);
  var count = 0;
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final p = image.getPixel(x, y);
      final luma = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(
        0,
        255,
      );
      histogram[luma] += 1;
      count++;
    }
  }
  if (count <= 0) return _averageLuma(image);

  final lowTrim = (count * 0.08).round();
  final highTrim = (count * 0.92).round();
  var cumulative = 0;
  var weighted = 0.0;
  var kept = 0;
  for (var i = 0; i < histogram.length; i++) {
    final binCount = histogram[i];
    if (binCount == 0) continue;
    final start = cumulative;
    final end = cumulative + binCount;
    cumulative = end;

    final keepStart = math.max(start, lowTrim);
    final keepEnd = math.min(end, highTrim);
    final keep = keepEnd - keepStart;
    if (keep <= 0) continue;

    weighted += i * keep;
    kept += keep;
  }

  if (kept <= 0) return _averageLuma(image);
  return (weighted / kept / 255.0).clamp(0.0, 1.0).toDouble();
}

double _averageLuma(img.Image image) {
  final rgb = image.getBytes(order: img.ChannelOrder.rgb);
  if (rgb.isEmpty) return 0.0;
  var sum = 0.0;
  for (var i = 0; i < rgb.length; i += 3) {
    sum += (0.299 * rgb[i] + 0.587 * rgb[i + 1] + 0.114 * rgb[i + 2]) / 255.0;
  }
  return (sum / (rgb.length / 3)).clamp(0.0, 1.0).toDouble();
}

double _lumaStdDev(img.Image image, [double? mean]) {
  final width = image.width;
  final height = image.height;
  if (width <= 0 || height <= 0) return 0.0;
  final m = mean ?? _averageLuma(image);
  var accum = 0.0;
  final total = width * height;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final p = image.getPixel(x, y);
      final luma = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b) / 255.0;
      final d = luma - m;
      accum += d * d;
    }
  }
  return math.sqrt(accum / math.max(1, total));
}

double _computeAutoSharpenAmount({
  required double sharpnessQuality,
  required double lumaStdDev,
  required double maxSharpenAmount,
}) {
  final lowContrastSeverity = ((0.13 - lumaStdDev).clamp(0.0, 0.13) / 0.13)
      .clamp(0.0, 1.0)
      .toDouble();
  final blurSeverity = ((0.42 - sharpnessQuality).clamp(0.0, 0.42) / 0.42)
      .clamp(0.0, 1.0)
      .toDouble();
  return (blurSeverity * 0.86 + lowContrastSeverity * 0.22)
      .clamp(0.0, maxSharpenAmount)
      .toDouble();
}

img.Image _sharpenFaceCrop(img.Image source, double amount) {
  final safeAmount = amount.clamp(0.0, 1.0).toDouble();
  if (safeAmount <= 0.0) {
    return source;
  }

  final blurred = img.gaussianBlur(img.Image.from(source), radius: 1);
  final out = img.Image.from(source);
  for (var y = 0; y < out.height; y++) {
    for (var x = 0; x < out.width; x++) {
      final p = source.getPixel(x, y);
      final b = blurred.getPixel(x, y);

      int sharpenChannel(int orig, int blur) {
        final boosted = orig + (orig - blur) * safeAmount;
        return boosted.round().clamp(0, 255);
      }

      out.setPixelRgba(
        x,
        y,
        sharpenChannel(p.r.toInt(), b.r.toInt()),
        sharpenChannel(p.g.toInt(), b.g.toInt()),
        sharpenChannel(p.b.toInt(), b.b.toInt()),
        p.a.toInt(),
      );
    }
  }
  return out;
}

double _regionQuality(img.Image image, {required double minSharpness}) {
  final sharpnessScore = (_imageSharpness(image) / minSharpness).clamp(
    0.0,
    1.0,
  );
  final luminance = _robustFaceLuminance(image);
  final lightBalance = (1.0 - ((luminance - 0.5).abs() * 2.0)).clamp(
    0.0,
    1.0,
  );
  return (sharpnessScore * 0.78 + lightBalance * 0.22)
      .clamp(0.0, 1.0)
      .toDouble();
}
