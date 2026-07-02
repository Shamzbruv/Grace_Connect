import 'package:flutter/material.dart';

Future<void> showProfilePhotoViewer({
  required BuildContext context,
  required String imageUrl,
  required String displayName,
  VoidCallback? onChangePhoto,
}) async {
  final cleanUrl = imageUrl.trim();
  if (cleanUrl.isEmpty) return;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: Center(
                    child: Image.network(
                      cleanUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.broken_image_outlined,
                              color: Colors.white,
                              size: 48,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Photo could not load.',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                top: 8,
                child: Row(
                  children: [
                    IconButton.filled(
                      tooltip: 'Close',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        displayName.trim().isEmpty
                            ? 'Profile photo'
                            : displayName.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    if (onChangePhoto != null)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          onChangePhoto();
                        },
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Change'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
