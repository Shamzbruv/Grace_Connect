import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class PickedProfilePhoto {
  const PickedProfilePhoto({
    required this.bytes,
    required this.fileName,
  });

  final Uint8List bytes;
  final String fileName;
}

Future<PickedProfilePhoto?> pickProfilePhotoWithCropOption(
  BuildContext context,
) async {
  final image = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 1600,
    imageQuality: 92,
  );
  if (image == null) return null;

  final originalBytes = await image.readAsBytes();
  final croppedBytes = await _centerSquareCrop(originalBytes);
  if (!context.mounted) return null;

  final useCrop = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(sheetContext).padding.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Profile Photo',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _PhotoOptionCard(
                    label: 'Original',
                    child: Image.memory(originalBytes, fit: BoxFit.cover),
                    onTap: () => Navigator.pop(sheetContext, false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PhotoOptionCard(
                    label: 'Square crop',
                    child: croppedBytes == null
                        ? Image.memory(originalBytes, fit: BoxFit.cover)
                        : Image.memory(croppedBytes, fit: BoxFit.cover),
                    onTap: () => Navigator.pop(sheetContext, true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(sheetContext, true),
                icon: const Icon(Icons.crop_square_outlined),
                label: const Text('Use Square Crop'),
              ),
            ),
          ],
        ),
      );
    },
  );

  if (useCrop == null) return null;
  return PickedProfilePhoto(
    bytes: useCrop ? (croppedBytes ?? originalBytes) : originalBytes,
    fileName: useCrop ? _croppedFileName(image.name) : image.name,
  );
}

class _PhotoOptionCard extends StatelessWidget {
  const _PhotoOptionCard({
    required this.label,
    required this.child,
    required this.onTap,
  });

  final String label;
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.16),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: child,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<Uint8List?> _centerSquareCrop(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final side = math.min(image.width, image.height).toDouble();
    final source = ui.Rect.fromLTWH(
      (image.width - side) / 2,
      (image.height - side) / 2,
      side,
      side,
    );
    const targetSize = 900;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      image,
      source,
      const ui.Rect.fromLTWH(0, 0, 900, 900),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final croppedImage = await picture.toImage(targetSize, targetSize);
    final data = await croppedImage.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

String _croppedFileName(String originalName) {
  final base = originalName.trim().isEmpty
      ? 'profile'
      : originalName.split('/').last.split('.').first;
  return '${base}_square_${DateTime.now().millisecondsSinceEpoch}.png';
}
