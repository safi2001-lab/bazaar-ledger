import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../audit/when.dart';

/// An entry's photographs, one at a time and full size (M60).
///
/// Pinched to zoom, because the reason anybody opens a photograph of a
/// parchi is to read one figure on it — "was it forty bags or fourteen?" —
/// and that figure is a few millimetres of handwriting. Swiped between, for
/// a supplier's bill of several pages. Each says who put it on and when,
/// which is the next question after "what does it say".
///
/// Taking one off is offered to whoever may put entries right, and asks a
/// PIN when Data Lock is on, through the write path's own prompt. What is
/// taken off waits in the recycle bin.
class PhotoViewerScreen extends ConsumerStatefulWidget {
  const PhotoViewerScreen({
    super.key,
    required this.photos,
    this.initialIndex = 0,
  });

  final List<EntryPhoto> photos;
  final int initialIndex;

  @override
  ConsumerState<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends ConsumerState<PhotoViewerScreen> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  bool _busy = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _remove(EntryPhoto photo) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(s.photoRemoveConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.commonNo),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.commonYes),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await ref.read(appServicesProvider).photos.remove(photo.id);
      container.bumpRefresh();
      messenger.showSnackBar(SnackBar(content: Text(s.photoRemoved)));
      navigator.pop();
    } on Object catch (error) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (error) {
            PhotoRefused(:final reason) => reason,
            PermissionDenied(:final reason) => reason,
            ApprovalNeeded() => '$error',
            _ => '${s.commonSomethingWentWrong}: $error',
          }),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final photos = widget.photos;
    final photo = photos[_index];
    final mayRemove = ref.watch(appServicesProvider).photos.mayRemove;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text('${_index + 1} / ${photos.length}'),
        actions: [
          if (mayRemove)
            BlIconButton(
              icon: Icons.delete_outline,
              label: s.pictureRemove,
              colour: t.danger,
              onPressed: _busy ? null : () => unawaited(_remove(photo)),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: photos.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => InteractiveViewer(
                  maxScale: 6,
                  child: Center(
                    child: Image.memory(
                      photos[i].bytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      semanticLabel: s.photoOpen(i + 1),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(BlTokens.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    s.photoAddedBy(
                      photo.addedBy,
                      shopTime(photo.addedAtUtc.millisecondsSinceEpoch),
                    ),
                    style: TextStyle(fontSize: 13, color: t.inkMuted),
                  ),
                  if (photo.fromEarlierEntry)
                    Padding(
                      padding: const EdgeInsets.only(top: BlTokens.space1),
                      child: Text(
                        s.photoFromEarlier,
                        style: TextStyle(fontSize: 13, color: t.accent),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
