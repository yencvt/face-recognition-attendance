import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../database/face_attendance_repository.dart';

enum _Corner { topLeft, topRight, bottomLeft, bottomRight }

class RecognitionZoneEditorDialog extends StatefulWidget {
  const RecognitionZoneEditorDialog({
    required this.zone,
    required this.cameraName,
    this.renderer,
    this.mirrorHorizontally = false,
    super.key,
  });

  final RecognitionZone zone;
  final String cameraName;
  final RTCVideoRenderer? renderer;
  final bool mirrorHorizontally;

  @override
  State<RecognitionZoneEditorDialog> createState() => _RecognitionZoneEditorDialogState();
}

class _RecognitionZoneEditorDialogState extends State<RecognitionZoneEditorDialog> {
  late RecognitionZone _zone;

  @override
  void initState() {
    super.initState();
    _zone = _toViewZone(widget.zone);
  }

  RecognitionZone _toViewZone(RecognitionZone zone) {
    if (!widget.mirrorHorizontally) return zone;
    final mirroredLeft = 1 - zone.leftRatio - zone.widthRatio;
    final mirroredRotation = (360 - zone.rotationDegrees) % 360;
    return zone.copyWith(
      leftRatio: mirroredLeft,
      rotationDegrees: mirroredRotation,
    );
  }

  RecognitionZone _toStoredZone(RecognitionZone zone) {
    if (!widget.mirrorHorizontally) return zone;
    final originalLeft = 1 - zone.leftRatio - zone.widthRatio;
    final originalRotation = (360 - zone.rotationDegrees) % 360;
    return zone.copyWith(
      leftRatio: originalLeft,
      rotationDegrees: originalRotation,
    );
  }

  double _clamp(double v, {double min = 0, double max = 1}) => v.clamp(min, max).toDouble();

  void _setZone(RecognitionZone zone) {
    final width = _clamp(zone.widthRatio, min: 0.15, max: 0.95);
    final height = _clamp(zone.heightRatio, min: 0.15, max: 0.95);
    final left = _clamp(zone.leftRatio, min: 0, max: 1 - width);
    final top = _clamp(zone.topRatio, min: 0, max: 1 - height);

    setState(() {
      _zone = zone.copyWith(
        leftRatio: left,
        topRatio: top,
        widthRatio: width,
        heightRatio: height,
        rotationDegrees: ((zone.rotationDegrees % 360) + 360) % 360,
      );
    });
  }

  void _move(Offset delta, Size canvas) {
    _setZone(_zone.copyWith(
      leftRatio: _zone.leftRatio + delta.dx / canvas.width,
      topRatio: _zone.topRatio + delta.dy / canvas.height,
    ));
  }

  void _rotateToGlobalPosition(Offset globalPosition, Size canvas, RenderBox canvasBox) {
    final left = _zone.leftRatio * canvas.width;
    final top = _zone.topRatio * canvas.height;
    final width = _zone.widthRatio * canvas.width;
    final height = _zone.heightRatio * canvas.height;
    final centerLocal = Offset(left + width / 2, top + height / 2);
    final centerGlobal = canvasBox.localToGlobal(centerLocal);

    final angle = math.atan2(
      globalPosition.dy - centerGlobal.dy,
      globalPosition.dx - centerGlobal.dx,
    );

    final degrees = (angle * 180 / math.pi + 90 + 360) % 360;
    _setZone(_zone.copyWith(rotationDegrees: degrees));
  }

  void _resize(_Corner c, Offset delta, Size canvas) {
    final dx = delta.dx / canvas.width;
    final dy = delta.dy / canvas.height;
    double left = _zone.leftRatio;
    double top = _zone.topRatio;
    double width = _zone.widthRatio;
    double height = _zone.heightRatio;

    switch (c) {
      case _Corner.topLeft:
        left += dx;
        top += dy;
        width -= dx;
        height -= dy;
        break;
      case _Corner.topRight:
        top += dy;
        width += dx;
        height -= dy;
        break;
      case _Corner.bottomLeft:
        left += dx;
        width -= dx;
        height += dy;
        break;
      case _Corner.bottomRight:
        width += dx;
        height += dy;
        break;
    }

    _setZone(_zone.copyWith(leftRatio: left, topRatio: top, widthRatio: width, heightRatio: height));
  }

  Widget _handle(_Corner c, Alignment align, Size canvas) {
    return Align(
      alignment: align,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) => _resize(c, d.delta, canvas),
        child: SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.indigo.shade400, width: 1.8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = math.min(960.0, constraints.maxWidth);
            final h = math.min(740.0, constraints.maxHeight);
            return SizedBox(
              width: w,
              height: h,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Cau hinh vung nhan dien', style: Theme.of(context).textTheme.titleLarge),
                              Text('Camera: ${widget.cameraName}', style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                        Switch(
                          value: _zone.enabled,
                          onChanged: (v) => _setZone(_zone.copyWith(enabled: v)),
                        ),
                        IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Keo khung de di chuyen, keo 4 goc de thu phong, giu nut xoay de xoay truc tiep trong khung.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: LayoutBuilder(
                          builder: (context, box) {
                            final canvas = Size(box.maxWidth, box.maxHeight);
                            final left = _zone.leftRatio * canvas.width;
                            final top = _zone.topRatio * canvas.height;
                            final width = _zone.widthRatio * canvas.width;
                            final height = _zone.heightRatio * canvas.height;
                            final center = Offset(left + width / 2, top + height / 2);
                            final rotateAngle = _zone.rotationDegrees * math.pi / 180;
                            final topEdgeDirection = Offset(
                              math.sin(rotateAngle),
                              -math.cos(rotateAngle),
                            );
                            final topEdgeAnchor = Offset(
                              center.dx + topEdgeDirection.dx * (height / 2),
                              center.dy + topEdgeDirection.dy * (height / 2),
                            );
                            final rotateHandleCenter = Offset(
                              topEdgeAnchor.dx + topEdgeDirection.dx * 10,
                              topEdgeAnchor.dy + topEdgeDirection.dy * 10,
                            );
                            final canvasBox = context.findRenderObject() as RenderBox;

                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                if (widget.renderer != null && widget.renderer!.renderVideo)
                                  Transform(
                                    alignment: Alignment.center,
                                    transform: widget.mirrorHorizontally
                                        ? Matrix4.diagonal3Values(-1.0, 1.0, 1.0)
                                        : Matrix4.identity(),
                                    child: RTCVideoView(widget.renderer!),
                                  )
                                else
                                  Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [Colors.blueGrey.shade900, Colors.black87],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                    ),
                                    child: const Center(
                                      child: Text(
                                        'Chua co preview camera',
                                        style: TextStyle(color: Colors.white70),
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  left: left,
                                  top: top,
                                  width: width,
                                  height: height,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onPanUpdate: (d) => _move(d.delta, canvas),
                                    child: Transform.rotate(
                                      angle: _zone.rotationDegrees * math.pi / 180,
                                      alignment: Alignment.center,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: Colors.amberAccent, width: 2.5),
                                          color: Colors.amberAccent.withValues(alpha: 0.08),
                                        ),
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            Positioned(
                                              left: 8,
                                              top: 8,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: Colors.black.withValues(alpha: 0.55),
                                                  borderRadius: BorderRadius.circular(999),
                                                ),
                                                child: Text(_zone.label, style: const TextStyle(color: Colors.white, fontSize: 12)),
                                              ),
                                            ),
                                            _handle(_Corner.topLeft, Alignment.topLeft, canvas),
                                            _handle(_Corner.topRight, Alignment.topRight, canvas),
                                            _handle(_Corner.bottomLeft, Alignment.bottomLeft, canvas),
                                            _handle(_Corner.bottomRight, Alignment.bottomRight, canvas),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: CustomPaint(
                                      painter: _RotateGuidePainter(
                                        center: topEdgeAnchor,
                                        handleCenter: rotateHandleCenter,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: rotateHandleCenter.dx - 28,
                                  top: rotateHandleCenter.dy - 28,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onPanStart: (d) => _rotateToGlobalPosition(d.globalPosition, canvas, canvasBox),
                                    onPanUpdate: (d) => _rotateToGlobalPosition(d.globalPosition, canvas, canvasBox),
                                    child: SizedBox(
                                      width: 56,
                                      height: 56,
                                      child: Center(
                                        child: Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.indigo, width: 1.8),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.22),
                                                blurRadius: 7,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(Icons.rotate_right, size: 16, color: Colors.indigo),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    child: Row(
                      children: [
                        Expanded(child: OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Huy'))),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              Navigator.of(context).pop(
                                _toStoredZone(_zone).copyWith(
                                  updatedAt: DateTime.now().millisecondsSinceEpoch,
                                ),
                              );
                            },
                            child: const Text('Luu vung'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RotateGuidePainter extends CustomPainter {
  const _RotateGuidePainter({required this.center, required this.handleCenter});

  final Offset center;
  final Offset handleCenter;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(center, handleCenter, paint);
  }

  @override
  bool shouldRepaint(covariant _RotateGuidePainter oldDelegate) {
    return oldDelegate.center != center || oldDelegate.handleCenter != handleCenter;
  }
}
