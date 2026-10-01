import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/reel.dart';
import '../../services/reel_service.dart';
import '../../screens/reels/reel_grace_screen.dart';

Future<void> openReel(BuildContext context, String id) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
          builder: (_) => Scaffold(
                backgroundColor: Colors.black,
                appBar: AppBar(title: const Text('Reel Grace')),
                body: ReelGraceScreen(isActive: true, reelId: id),
              )),
    );

class ProfileReelsGrid extends StatefulWidget {
  const ProfileReelsGrid({super.key, required this.authorId});
  final String authorId;
  @override
  State<ProfileReelsGrid> createState() => _ProfileReelsGridState();
}

class _ProfileReelsGridState extends State<ProfileReelsGrid> {
  final _service = ReelService();
  final List<Reel> _reels = [];
  Map<String, dynamic>? _cursor;
  bool _loading = false;
  bool _hasMore = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page =
          await _service.fetchProfile(widget.authorId, cursor: _cursor);
      await _service.ensureMedia(page.reels.map((r) => r.id));
      if (!mounted) return;
      setState(() {
        final ids = _reels.map((r) => r.id).toSet();
        _reels.addAll(page.reels.where((r) => ids.add(r.id)));
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_reels.isEmpty && !_loading && !_failed)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No reels to show yet.')),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _reels.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 9 / 16,
                crossAxisSpacing: 3,
                mainAxisSpacing: 3),
            itemBuilder: (context, index) {
              final reel = _reels[index];
              final poster = _service.cachedMedia(reel.id)?.posterUrl;
              return Semantics(
                label: 'Play reel: ${reel.caption}',
                button: true,
                child: InkWell(
                    onTap: () => openReel(context, reel.id),
                    child: Stack(fit: StackFit.expand, children: [
                      const ColoredBox(color: Colors.black87),
                      if (poster != null)
                        CachedNetworkImage(
                            imageUrl: poster,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => const Icon(
                                Icons.movie_outlined,
                                color: Colors.white70)),
                      const Positioned(
                          bottom: 8,
                          left: 8,
                          child: Icon(Icons.play_arrow_rounded,
                              color: Colors.white)),
                      if (reel.visibility != ReelVisibility.public)
                        const Positioned(
                            top: 8,
                            right: 8,
                            child: Icon(Icons.lock_outline,
                                size: 16, color: Colors.white)),
                    ])),
              );
            },
          ),
          if (_loading)
            const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator())),
          if (!_loading && (_failed || _hasMore))
            TextButton(
                onPressed: _load,
                child:
                    Text(_failed ? 'Retry loading reels' : 'Load more reels')),
        ],
      );
}
