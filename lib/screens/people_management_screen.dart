import 'dart:convert';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../database/face_attendance_repository.dart';
import '../services/camera_stream_service.dart';
import '../services/face_recognition_service.dart';
import 'face_camera_capture_screen.dart';

class PeopleManagementScreen extends StatefulWidget {
  const PeopleManagementScreen({super.key});

  @override
  State<PeopleManagementScreen> createState() => _PeopleManagementScreenState();
}

class _PeopleManagementScreenState extends State<PeopleManagementScreen> {
  static const List<String> _poseLabels = <String>[
    'Chinh dien',
    'Trai',
    'Phai',
    'Tren',
    'Duoi',
  ];

  List<FacePerson> _people = const [];
  bool _loading = true;
  bool _rebuildingAll = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final people = await FaceAttendanceRepository.getPeople();
    if (!mounted) return;
    setState(() {
      _people = people;
      _loading = false;
    });
  }

  Future<void> _rebuildVectors(FacePerson person) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('Dang tinh lai vector cho ${person.name}...')),
    );

    try {
      await FaceRecognitionService.instance.rebuildVectorsForPerson(person.id);
      final entries =
          await FaceAttendanceRepository.getVectorCacheEntriesForPerson(
            person.id,
          );
      await _reload();
      if (!mounted) return;
      if (entries.isEmpty) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Khong tao duoc vector cho ${person.name}. Vui long upload/chup lai anh ro net.',
            ),
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Da cap nhat ${entries.length} vector va nap lai RAM cho ${person.name}',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Tinh lai vector that bai: $e')),
      );
    }
  }

  Future<void> _rebuildAllVectors() async {
    if (_rebuildingAll) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _rebuildingAll = true;
    });

    messenger.showSnackBar(
      const SnackBar(content: Text('Dang tinh lai vector cho tat ca nguoi...')),
    );

    try {
      await FaceRecognitionService.instance.rebuildVectorsForAllPeople();
      final people = await FaceAttendanceRepository.getPeople();
      var okCount = 0;
      final emptyNames = <String>[];
      for (final person in people) {
        final entries =
            await FaceAttendanceRepository.getVectorCacheEntriesForPerson(
              person.id,
            );
        if (entries.isEmpty) {
          emptyNames.add(person.name);
        } else {
          okCount++;
        }
      }

      await _reload();
      if (!mounted) return;

      final failedCount = emptyNames.length;
      if (failedCount == 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Da tinh lai vector thanh cong cho $okCount/${people.length} nguoi.',
            ),
          ),
        );
      } else {
        final preview = emptyNames.take(5).join(', ');
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Hoan tat tinh lai vector: thanh cong $okCount/${people.length}, that bai $failedCount. Kiem tra lai anh cua: $preview',
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Tinh lai tat ca vector that bai: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _rebuildingAll = false;
        });
      }
    }
  }

  Future<void> _openEditor({FacePerson? person}) async {
    final nameController = TextEditingController(text: person?.name ?? '');
    final codeController = TextEditingController(
      text: person?.employeeCode ?? '',
    );
    final departmentController = TextEditingController(
      text: person?.department ?? '',
    );
    final notesController = TextEditingController(text: person?.notes ?? '');
    final originalImages = List<Uint8List?>.filled(_poseLabels.length, null);
    final croppedImages = List<Uint8List?>.filled(_poseLabels.length, null);

    if (person != null) {
      if (person.imageBase64.isNotEmpty) {
        originalImages[0] = base64Decode(person.imageBase64);
      }
      final primaryPreview = person.imageCropBase64.isNotEmpty
          ? person.imageCropBase64
          : person.imageBase64;
      if (primaryPreview.isNotEmpty) {
        croppedImages[0] = base64Decode(primaryPreview);
      }

      final extraImages = await FaceAttendanceRepository.getPersonImages(
        person.id,
      );
      var slot = 1;
      for (final image in extraImages) {
        if (image.imageBase64.isEmpty) continue;
        if (slot >= croppedImages.length) break;
        originalImages[slot] = base64Decode(image.imageBase64);
        final preview = image.imageCropBase64.isNotEmpty
            ? image.imageCropBase64
            : image.imageBase64;
        if (preview.isNotEmpty) {
          croppedImages[slot] = base64Decode(preview);
        }
        slot++;
      }
    }

    if (!mounted) return;

    final hoverBySlot = List<bool>.filled(_poseLabels.length, false);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final messenger = ScaffoldMessenger.of(dialogContext);

            Future<void> processImageForSlot(int index, Uint8List bytes) async {
              final preprocessed = await FaceRecognitionService.instance
                  .preprocessEnrollmentImage(
                    bytes,
                    poseLabel: _poseLabels[index],
                  );
              if (!preprocessed.ok || preprocessed.imageBytes == null) {
                messenger.showSnackBar(
                  SnackBar(content: Text(preprocessed.message)),
                );
                return;
              }

              setDialogState(() {
                originalImages[index] = bytes;
                croppedImages[index] = preprocessed.imageBytes;
              });
            }

            Future<void> uploadImages() async {
              final count = croppedImages.where((e) => e != null).length;
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    'Dang co $count/5 anh. Hay upload tung vi tri ben duoi hoac chon chup bo 5 goc.',
                  ),
                ),
              );
            }

            Future<void> uploadImageAt(int index) async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.image,
                allowMultiple: false,
                withData: true,
              );

              final pickedFiles = result?.files ?? const [];
              final bytes = pickedFiles.isEmpty
                  ? null
                  : pickedFiles.first.bytes;
              if (bytes == null || bytes.isEmpty) return;
              await processImageForSlot(index, bytes);
            }

            Future<void> handleDropAt(
              int index,
              DropDoneDetails details,
            ) async {
              if (details.files.isEmpty) return;
              final dropped = details.files.first;
              final bytes = await dropped.readAsBytes();
              if (bytes.isEmpty) return;
              await processImageForSlot(index, bytes);
            }

            Future<void> captureImage() async {
              final navigator = Navigator.of(dialogContext);
              final streamSnapshot = CameraStreamService.instance.current;
              final runningCameraIds = streamSnapshot.sessions
                  .where(
                    (session) =>
                        FaceRecognitionService.instance.isRunning(session.id),
                  )
                  .map((session) => session.id)
                  .toList(growable: false);

              await FaceRecognitionService.instance.stopAllProcessors();

              List<Uint8List>? captured;
              try {
                captured = await navigator.push<List<Uint8List>>(
                  MaterialPageRoute(
                    builder: (_) => const FaceCameraCaptureScreen(),
                  ),
                );
              } finally {
                for (final cameraId in runningCameraIds) {
                  final preferredIndex = streamSnapshot.sessions.indexWhere(
                    (session) => session.id == cameraId,
                  );
                  try {
                    await FaceRecognitionService.instance
                        .ensureProcessorForCamera(
                          cameraId,
                          preferredDeviceIndex: preferredIndex >= 0
                              ? preferredIndex
                              : 0,
                        );
                  } catch (_) {
                    // Do not block enrollment flow if processor restore fails.
                  }
                }
              }

              if (captured == null || captured.isEmpty) return;

              final processed = <Uint8List>[];
              for (
                var i = 0;
                i < captured.length && i < _poseLabels.length;
                i++
              ) {
                final preprocessed = await FaceRecognitionService.instance
                    .preprocessEnrollmentImage(
                      captured[i],
                      poseLabel: _poseLabels[i],
                    );
                if (!preprocessed.ok || preprocessed.imageBytes == null) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(preprocessed.message)),
                  );
                  return;
                }
                processed.add(preprocessed.imageBytes!);
              }

              setDialogState(() {
                for (var i = 0; i < _poseLabels.length; i++) {
                  originalImages[i] = i < captured!.length ? captured[i] : null;
                  croppedImages[i] = i < processed.length ? processed[i] : null;
                }
              });
            }

            void removeImageAt(int index) {
              setDialogState(() {
                originalImages[index] = null;
                croppedImages[index] = null;
              });
            }

            return AlertDialog(
              title: Text(person == null ? 'Them nguoi' : 'Cap nhat thong tin'),
              content: SizedBox(
                width: 760,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Theme.of(context).colorScheme.primaryContainer
                                  .withValues(alpha: 0.36),
                              Theme.of(context).colorScheme.surface,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.15),
                              child: Icon(
                                Icons.add_photo_alternate_rounded,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Upload anh theo 5 vi tri',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Keo tha file vao tung o hoac bam truc tiep vao o de chon anh. Da chon: ${croppedImages.where((e) => e != null).length}/5',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton.tonalIcon(
                              onPressed: captureImage,
                              icon: const Icon(Icons.camera_alt),
                              label: const Text('Chup 5 goc'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 246,
                        child: GridView.builder(
                          itemCount: _poseLabels.length,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 5,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 0.62,
                              ),
                          itemBuilder: (context, index) {
                            final bytes = croppedImages[index];
                            final isPrimary = index == 0;
                            final isHovering = hoverBySlot[index];
                            return Column(
                              children: [
                                Text(
                                  _poseLabels[index],
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        fontWeight: isPrimary
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Expanded(
                                  child: Stack(
                                    children: [
                                      DropTarget(
                                        onDragEntered: (_) {
                                          setDialogState(() {
                                            hoverBySlot[index] = true;
                                          });
                                        },
                                        onDragExited: (_) {
                                          setDialogState(() {
                                            hoverBySlot[index] = false;
                                          });
                                        },
                                        onDragDone: (details) async {
                                          setDialogState(() {
                                            hoverBySlot[index] = false;
                                          });
                                          await handleDropAt(index, details);
                                        },
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            onTap: () => uploadImageAt(index),
                                            child: AnimatedContainer(
                                              duration: const Duration(
                                                milliseconds: 170,
                                              ),
                                              width: double.infinity,
                                              decoration: BoxDecoration(
                                                color: isHovering
                                                    ? Theme.of(context)
                                                          .colorScheme
                                                          .primaryContainer
                                                          .withValues(
                                                            alpha: 0.38,
                                                          )
                                                    : Theme.of(
                                                        context,
                                                      ).colorScheme.surface,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: isHovering
                                                      ? Theme.of(
                                                          context,
                                                        ).colorScheme.primary
                                                      : (isPrimary
                                                            ? Theme.of(context)
                                                                  .colorScheme
                                                                  .primary
                                                            : Theme.of(context)
                                                                  .colorScheme
                                                                  .outlineVariant),
                                                  width: isPrimary || isHovering
                                                      ? 2
                                                      : 1,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(
                                                          alpha: isHovering
                                                              ? 0.12
                                                              : 0.05,
                                                        ),
                                                    blurRadius: isHovering
                                                        ? 18
                                                        : 10,
                                                    offset: const Offset(0, 6),
                                                  ),
                                                ],
                                              ),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(11),
                                                child: bytes == null
                                                    ? Column(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        children: [
                                                          Icon(
                                                            isHovering
                                                                ? Icons
                                                                      .file_download_done
                                                                : Icons
                                                                      .upload_file_rounded,
                                                            color:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .primary,
                                                            size: 28,
                                                          ),
                                                          const SizedBox(
                                                            height: 6,
                                                          ),
                                                          Text(
                                                            isHovering
                                                                ? 'Tha file vao day'
                                                                : 'Keo tha\nhoac Bam vao o',
                                                            textAlign: TextAlign
                                                                .center,
                                                            style:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .textTheme
                                                                    .labelSmall,
                                                          ),
                                                        ],
                                                      )
                                                    : Image.memory(
                                                        bytes,
                                                        fit: BoxFit.cover,
                                                      ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (bytes != null)
                                        Positioned(
                                          top: 6,
                                          right: 6,
                                          child: InkWell(
                                            onTap: () => removeImageAt(index),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(
                                                  alpha: 0.55,
                                                ),
                                                shape: BoxShape.circle,
                                              ),
                                              padding: const EdgeInsets.all(4),
                                              child: const Icon(
                                                Icons.close,
                                                size: 13,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: uploadImages,
                          icon: const Icon(Icons.info_outline),
                          label: const Text('Huong dan upload'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Ho va ten',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: codeController,
                        decoration: const InputDecoration(
                          labelText: 'Ma nhan vien',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: departmentController,
                        decoration: const InputDecoration(
                          labelText: 'Phong ban',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: notesController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Ghi chu',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Huy'),
                ),
                FilledButton(
                  onPressed: () async {
                    final navigator = Navigator.of(dialogContext);
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Vui long nhap ho va ten'),
                        ),
                      );
                      return;
                    }
                    final orderedOriginal = originalImages
                        .whereType<Uint8List>()
                        .toList(growable: false);
                    final orderedCrop = croppedImages
                        .whereType<Uint8List>()
                        .toList(growable: false);
                    if (orderedOriginal.length != 5 ||
                        orderedCrop.length != 5) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Vui long cung cap du 5 anh: chinh dien, trai, phai, tren, duoi',
                          ),
                        ),
                      );
                      return;
                    }

                    final item = FacePerson(
                      id:
                          person?.id ??
                          DateTime.now().microsecondsSinceEpoch.toString(),
                      name: name,
                      employeeCode: codeController.text.trim(),
                      department: departmentController.text.trim(),
                      notes: notesController.text.trim(),
                      imageBase64: base64Encode(orderedOriginal.first),
                      imageCropBase64: base64Encode(orderedCrop.first),
                      createdAt:
                          person?.createdAt ??
                          DateTime.now().millisecondsSinceEpoch,
                    );
                    try {
                      await FaceAttendanceRepository.savePerson(item);
                      await FaceAttendanceRepository.replacePersonImages(
                        item.id,
                        orderedOriginal
                            .skip(1)
                            .map(base64Encode)
                            .toList(growable: false),
                        imageCropBase64List: orderedCrop
                            .skip(1)
                            .map(base64Encode)
                            .toList(growable: false),
                      );

                      await FaceRecognitionService.instance
                          .rebuildVectorsForPerson(item.id);
                      final entries =
                          await FaceAttendanceRepository.getVectorCacheEntriesForPerson(
                            item.id,
                          );
                      if (entries.isEmpty) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Da luu thong tin nhung chua tao duoc vector. Vui long chup/upload lai anh ro net va bam "Tinh lai vector".',
                            ),
                          ),
                        );
                      }

                      if (!mounted) return;
                      navigator.pop();
                      await _reload();
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Luu that bai: $e')),
                      );
                    }
                  },
                  child: const Text('Luu'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _delete(FacePerson p) async {
    await FaceAttendanceRepository.deletePerson(p.id);
    await FaceRecognitionService.instance.refreshTemplates();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quan ly nguoi nhan dien'),
        actions: [
          TextButton.icon(
            onPressed: _rebuildingAll ? null : _rebuildAllVectors,
            icon: _rebuildingAll
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: Text(_rebuildingAll ? 'Dang tinh...' : 'Tinh lai tat ca'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.person_add),
        label: const Text('Them nguoi'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _people.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final p = _people[index];
                final subtitleParts = <String>[
                  if (p.employeeCode.isNotEmpty) p.employeeCode,
                  if (p.department.isNotEmpty) p.department,
                  if (p.notes.isNotEmpty) p.notes,
                ];

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundImage: p.imageBase64.isNotEmpty
                          ? MemoryImage(base64Decode(p.imageBase64))
                          : null,
                      child: p.imageBase64.isEmpty
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    title: Text(p.name),
                    subtitle: Text(subtitleParts.join(' • ')),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'edit') {
                          await _openEditor(person: p);
                        } else if (value == 'rebuild') {
                          await _rebuildVectors(p);
                        } else if (value == 'delete') {
                          await _delete(p);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'edit', child: Text('Chinh sua')),
                        PopupMenuItem(
                          value: 'rebuild',
                          child: Text('Tinh lai vector'),
                        ),
                        PopupMenuItem(value: 'delete', child: Text('Xoa')),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
