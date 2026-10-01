import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../models/post.dart';
import '../../models/reel.dart';
import '../../services/community_service.dart';
import '../../services/reel_service.dart';
import '../../screens/community/post_detail_screen.dart';
import '../profile/profile_reels_grid.dart';

class SharedContentCard extends StatefulWidget {
  const SharedContentCard({super.key, required this.reference});
  final Map<String, dynamic> reference;
  @override
  State<SharedContentCard> createState() => _SharedContentCardState();
}

class _SharedContentCardState extends State<SharedContentCard> {
  late Future<_Preview?> _preview = _load();
  Future<_Preview?> _load() async {
    final id = widget.reference['id']?.toString() ?? '';
    if (widget.reference['kind'] == 'reel') {
      final service = ReelService();
      final reel = await service.fetchDetail(id);
      if (reel == null) return null;
      await service.ensureMedia([id]);
      return _Preview(reel.authorName, reel.caption,
          service.cachedMedia(id)?.posterUrl, true,
          reel: reel);
    }
    if (widget.reference['kind'] == 'post') {
      final post = await CommunityService().fetchPostById(id);
      if (post == null) return null;
      final video = post.mediaType?.startsWith('video') == true;
      return _Preview(post.authorName, post.content,
          video ? post.mediaThumbnailUrl : post.mediaUrl, video,
          post: post);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
      width: 280,
      child: FutureBuilder<_Preview?>(
          future: _preview,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                  height: 180,
                  child: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.hasError) {
              return TextButton(
                  onPressed: () => setState(() => _preview = _load()),
                  child: const Text('Retry shared content'));
            }
            final preview = snapshot.data;
            if (preview == null) {
              return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('This content is no longer available to you.'));
            }
            final theme = Theme.of(context);
            return Material(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                    onTap: () {
                      if (preview.reel != null) {
                        openReel(context, preview.reel!.id);
                      } else {
                        Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                                builder: (_) =>
                                    PostDetailScreen(post: preview.post!)));
                      }
                    },
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (preview.image?.isNotEmpty == true ||
                              preview.video)
                            AspectRatio(
                                aspectRatio: preview.reel != null ? 9 / 13 : 1,
                                child: Stack(fit: StackFit.expand, children: [
                                  const ColoredBox(color: Colors.black87),
                                  if (preview.image?.isNotEmpty == true)
                                    CachedNetworkImage(
                                        imageUrl: preview.image!,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) => const Icon(
                                            Icons.image_not_supported_outlined,
                                            color: Colors.white70)),
                                  if (preview.video)
                                    const Center(
                                        child: Icon(Icons.play_circle_fill,
                                            size: 52, color: Colors.white)),
                                ])),
                          Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                              child: Text(preview.author,
                                  style: theme.textTheme.labelLarge,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis)),
                          Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: Text(
                                  preview.caption.isEmpty
                                      ? (preview.video
                                          ? 'Watch video'
                                          : 'View post')
                                      : preview.caption,
                                  style: theme.textTheme.bodyMedium,
                                  maxLines:
                                      preview.image == null && !preview.video
                                          ? 8
                                          : 3,
                                  overflow: TextOverflow.ellipsis)),
                        ])));
          }));
}

class _Preview {
  const _Preview(this.author, this.caption, this.image, this.video,
      {this.reel, this.post});
  final String author, caption;
  final String? image;
  final bool video;
  final Reel? reel;
  final Post? post;
}
