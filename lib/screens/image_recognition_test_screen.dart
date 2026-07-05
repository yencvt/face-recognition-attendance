import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../database/face_attendance_repository.dart';
import '../services/face_recognition_service.dart';

class ImageRecognitionTestScreen extends StatefulWidget {
  const ImageRecognitionTestScreen({super.key});

  @override
  State<ImageRecognitionTestScreen> createState() =>
      _ImageRecognitionTestScreenState();
}

class _ImageRecognitionTestScreenState
    extends State<ImageRecognitionTestScreen> {
  final FaceRecognitionService _service = FaceRecognitionService.instance;

  List<FacePerson> _people = const <FacePerson>[];
  final Set<String> _selectedPersonIds = <String>{};

  Uint8List? _originalImageBytes;
  String? _fileName;

  bool _isRunning = false;
  bool _isDraggingUpload = false;
  double _matchThreshold = 0.55;
  UploadedImageRecognitionResult? _result;

  @override
  void initState() {
    super.initState();
    _loadPeople();
  }

  Future<void> _loadPeople() async {
    final people = await FaceAttendanceRepository.getPeople();
    if (!mounted) return;
    setState(() {
      _people = people;
    });
  }

  Future<void> _pickImage() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (!mounted || picked == null || picked.files.isEmpty) {
      return;
    }

    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Khong doc duoc du lieu anh.')),
      );
      return;
    }

    _setSelectedImage(bytes, file.name);
  }

  Future<void> _onDropFiles(DropDoneDetails details) async {
    if (details.files.isEmpty) return;
    final dropped = details.files.first;

    Uint8List bytes = Uint8List(0);
    try {
      bytes = await dropped.readAsBytes();
      if (bytes.isEmpty && dropped.path.isNotEmpty) {
        bytes = await File(dropped.path).readAsBytes();
      }
    } catch (_) {
      if (dropped.path.isNotEmpty) {
        try {
          bytes = await File(dropped.path).readAsBytes();
        } catch (_) {}
      }
    }

    if (!mounted) return;
    if (bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Khong doc duoc anh tu file keo tha.')),
      );
      return;
    }

    final name = dropped.name.isNotEmpty
        ? dropped.name
        : (dropped.path.isNotEmpty
              ? dropped.path.split(RegExp(r'[/\\]')).last
              : 'dropped_image');
    _setSelectedImage(bytes, name);
  }

  void _setSelectedImage(Uint8List bytes, String fileName) {
    setState(() {
      _fileName = fileName;
      _originalImageBytes = bytes;
      _result = null;
    });
  }

  void _clearQuick() {
    setState(() {
      _fileName = null;
      _originalImageBytes = null;
      _result = null;
      _isDraggingUpload = false;
    });
  }

  Future<void> _runTest() async {
    if (_originalImageBytes == null || _originalImageBytes!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui long chon hoac keo tha anh truoc.')),
      );
      return;
    }
    if (_selectedPersonIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui long chon danh sach doi tuong.')),
      );
      return;
    }

    final selectedPeople = _people
        .where((p) => _selectedPersonIds.contains(p.id))
        .toList(growable: false);

    setState(() {
      _isRunning = true;
      _result = null;
    });

    try {
      final result = await _service
          .analyzeUploadedImage(
            imageBytes: _originalImageBytes!,
            selectedPeople: selectedPeople,
            matchThreshold: _matchThreshold,
          )
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      setState(() {
        _result = result;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _result = _buildSyntheticFailedResult(
          'Kiem tra qua 30s chua xong. Co the model dang treo hoac anh qua nang.',
        );
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Kiem tra bi timeout.')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _result = _buildSyntheticFailedResult('Loi khi chay kiem tra: $e');
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kiem tra that bai: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  UploadedImageRecognitionResult _buildSyntheticFailedResult(String message) {
    return UploadedImageRecognitionResult(
      pass: false,
      message: message,
      annotatedImageBytes: _originalImageBytes ?? Uint8List(0),
      matches: const <UploadedImageRecognitionFaceMatch>[],
      faceDebugInfos: const <UploadedImageRecognitionFaceDebugInfo>[],
      recognizedPersonIds: <String>{},
      missingPersonIds: _selectedPersonIds.toList(growable: false),
      matchThreshold: _matchThreshold,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test nhan dien tu anh upload')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1100;
            if (!wide) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildMainContent(context),
                    const SizedBox(height: 16),
                    _buildRightSelectionPanel(context),
                  ],
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: _buildMainContent(context),
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 360,
                    child: _buildRightSelectionPanel(context),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMainContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTopRegion(context),
        const SizedBox(height: 12),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: _isRunning ? null : _runTest,
                icon: _isRunning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_circle_fill),
                label: Text(_isRunning ? 'Dang kiem tra...' : 'Kiem tra'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _isRunning ? null : _clearQuick,
                icon: const Icon(Icons.clear),
                label: const Text('Clear'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildBottomRegion(context),
      ],
    );
  }

  Widget _buildTopRegion(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildImagePanel(
            context,
            title: 'Anh goc',
            bytes: _originalImageBytes,
            enableDrop: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildImagePanel(
            context,
            title: 'Anh ket qua (bbox)',
            bytes: _result?.annotatedImageBytes,
            enableDrop: false,
          ),
        ),
      ],
    );
  }

  Widget _buildImagePanel(
    BuildContext context, {
    required String title,
    required Uint8List? bytes,
    required bool enableDrop,
  }) {
    final isDropActive = _isDraggingUpload && enableDrop;
    final borderColor = isDropActive
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).dividerColor;

    final imageArea = AnimatedScale(
      scale: isDropActive ? 1.01 : 1.0,
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          border: Border.all(color: borderColor, width: isDropActive ? 3 : 1),
          borderRadius: BorderRadius.circular(12),
          boxShadow: isDropActive
              ? [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.24),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Stack(
              fit: StackFit.expand,
              children: [
                bytes != null && bytes.isNotEmpty
                    ? Image.memory(bytes, fit: BoxFit.contain)
                    : _buildUploadHint(enableDrop),
                if (isDropActive)
                  AnimatedOpacity(
                    opacity: isDropActive ? 1 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Container(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.08),
                      alignment: Alignment.center,
                      child: Text(
                        'Tha file de upload',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (enableDrop)
              DropTarget(
                onDragEntered: (_) {
                  setState(() {
                    _isDraggingUpload = true;
                  });
                },
                onDragExited: (_) {
                  setState(() {
                    _isDraggingUpload = false;
                  });
                },
                onDragDone: (details) async {
                  setState(() {
                    _isDraggingUpload = false;
                  });
                  await _onDropFiles(details);
                },
                child: InkWell(onTap: _pickImage, child: imageArea),
              )
            else
              imageArea,
            if (enableDrop) ...[
              const SizedBox(height: 8),
              Text(
                _fileName == null ? 'Chua chon anh' : 'File: $_fileName',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUploadHint(bool enableDrop) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                enableDrop ? Icons.upload_file : Icons.image_not_supported,
                size: 42,
              ),
              const SizedBox(height: 8),
              Text(
                enableDrop
                    ? 'Keo tha anh vao day\nhoac click de chon file'
                    : 'Chua co ket qua nhan dien',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomRegion(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Thong tin chi tiet ket qua',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _buildThresholdRow(context),
            const SizedBox(height: 8),
            _buildResultSummary(context),
            const SizedBox(height: 12),
            Text(
              'Danh sach face detect',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _buildFaceListTwoColumns(context),
          ],
        ),
      ),
    );
  }

  Widget _buildThresholdRow(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Match threshold: ${_matchThreshold.toStringAsFixed(2)}'),
        Slider(
          value: _matchThreshold,
          min: 0.30,
          max: 0.90,
          divisions: 60,
          label: _matchThreshold.toStringAsFixed(2),
          onChanged: _isRunning
              ? null
              : (value) {
                  setState(() {
                    _matchThreshold = value;
                  });
                },
        ),
      ],
    );
  }

  Widget _buildResultSummary(BuildContext context) {
    final result = _result;
    if (result == null) {
      return const Text('Chua co ket qua. Bam Kiem tra de chay nhan dien.');
    }

    final missingPeople = _people
        .where((p) => result.missingPersonIds.contains(p.id))
        .map((p) => p.name)
        .toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: result.pass
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.pass ? 'PASS' : 'FAILED',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(result.message),
          const SizedBox(height: 6),
          Text('So mat phat hien: ${result.matches.length}'),
          Text(
            'So doi tuong nhan dien duoc: ${result.recognizedPersonIds.length}',
          ),
          if (missingPeople.isNotEmpty)
            Text('Con thieu: ${missingPeople.join(', ')}'),
        ],
      ),
    );
  }

  Widget _buildFaceListTwoColumns(BuildContext context) {
    final result = _result;
    if (result == null || result.faceDebugInfos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Chua co danh sach face detect.'),
      );
    }

    return Column(
      children: result.faceDebugInfos
          .map((face) {
            final top1 = face.topCandidates.isEmpty
                ? 'N/A'
                : face.topCandidates.first.personName;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _showFaceZoomDialog(face),
                child: Ink(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Face #${face.faceIndex + 1} | det=${face.detectorScore.toStringAsFixed(3)} | top1=$top1',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildFaceColImage(
                              context,
                              title: 'Face goc',
                              bytes: face.originalFaceBytes,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildFaceColImage(
                              context,
                              title: 'Face da xu ly',
                              bytes: face.cleanedFaceBytes,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'rect=(${face.rect.left.toStringAsFixed(1)}, ${face.rect.top.toStringAsFixed(1)}, ${face.rect.width.toStringAsFixed(1)}, ${face.rect.height.toStringAsFixed(1)}) | '
                        'pixels=${face.minFacePixels} | vector=${face.vector.length}',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Click de phong to cap anh face',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }

  Future<void> _showFaceZoomDialog(UploadedImageRecognitionFaceDebugInfo face) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 760),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Face #${face.faceIndex + 1} - Phong to',
                          style: Theme.of(dialogContext).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildZoomPanel(
                            dialogContext,
                            title: 'Face goc',
                            bytes: face.originalFaceBytes,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildZoomPanel(
                            dialogContext,
                            title: 'Face da xu ly',
                            bytes: face.cleanedFaceBytes,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildZoomPanel(
    BuildContext context, {
    required String title,
    required Uint8List bytes,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 6,
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFaceColImage(
    BuildContext context, {
    required String title,
    required Uint8List bytes,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRightSelectionPanel(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedHeight = constraints.hasBoundedHeight;

        Widget peopleList() {
          final listView = ListView.builder(
            shrinkWrap: !hasBoundedHeight,
            itemCount: _people.length,
            itemBuilder: (context, index) {
              final person = _people[index];
              final selected = _selectedPersonIds.contains(person.id);
              return CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: selected,
                title: Text(person.name),
                subtitle: person.employeeCode.trim().isEmpty
                    ? null
                    : Text('Ma NV: ${person.employeeCode}'),
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _selectedPersonIds.add(person.id);
                    } else {
                      _selectedPersonIds.remove(person.id);
                    }
                  });
                },
              );
            },
          );

          if (hasBoundedHeight) {
            return Expanded(child: listView);
          }
          return SizedBox(height: 420, child: listView);
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Danh sach doi tuong',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (_people.isEmpty)
                  const Text('Danh sach nguoi trong he thong dang trong.')
                else
                  peopleList(),
              ],
            ),
          ),
        );
      },
    );
  }
}
