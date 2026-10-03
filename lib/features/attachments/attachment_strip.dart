import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'photo_viewer.dart';

/// Which entry a strip of photographs belongs to (M60).
///
/// Named by what it is rather than by table, so the one line each page
/// carries reads as what it means: the photographs of this payment, of this
/// bill, of this khata.
@immutable
final class AttachmentOwner {
  const AttachmentOwner._(this.table, this.id, this.kind);

  /// A bill, a delivery, an expense, a charge, a challan: anything kept as
  /// a document. What goes on it is the paper that came with it.
  const AttachmentOwner.document(String id)
    : this._('documents', id, EntryPhotoKind.receipt);

  /// Money in or out. A cheque's photograph is kept as one.
  const AttachmentOwner.payment(String id, {bool cheque = false})
    : this._(
        'payments',
        id,
        cheque ? EntryPhotoKind.cheque : EntryPhotoKind.receipt,
      );

  /// A customer's or a supplier's papers: a CNIC copy, a shop's card.
  const AttachmentOwner.party(String id)
    : this._('parties', id, EntryPhotoKind.papers);

  final String table;
  final String id;
  final EntryPhotoKind kind;

  /// A party's papers — usually a CNIC — which the strip says stay here.
  bool get isPapers => table == 'parties';

  @override
  bool operator ==(Object other) =>
      other is AttachmentOwner && other.table == table && other.id == id;

  @override
  int get hashCode => Object.hash(table, id);
}

/// The photographs on one entry, as they are now.
final entryPhotosProvider = FutureProvider.autoDispose
    .family<List<EntryPhoto>, AttachmentOwner>((ref, owner) async {
      ref.watch(refreshTickProvider);
      final services = ref.watch(appServicesProvider);
      final firm = await ref.watch(firmProvider.future);
      if (firm == null) return const [];
      return services.photos.of(owner.table, owner.id);
    });

/// The photographs of the paper behind an entry, and a way to add one.
///
/// One widget for every page that carries them — a payment, an expense, a
/// bill, a delivery, a challan, a khata — so each of those pages, which
/// belong to other milestones, carries one marked line and no more.
///
/// The camera or the gallery. The parchi is in the shopkeeper's hand, so
/// the camera is the first choice; it needs nothing the app did not already
/// have, because CAMERA has been declared since barcode scanning (M2), and
/// the gallery goes through Android's own photo picker, which needs no
/// permission at all.
class AttachmentStrip extends ConsumerStatefulWidget {
  const AttachmentStrip({
    super.key,
    required this.owner,
    this.padding = const EdgeInsets.symmetric(vertical: BlTokens.space2),
    this.compact = false,
  });

  /// For a page whose body is the paper itself — a bill, a delivery — where
  /// the strip sits above the paper at the page's own margins, and every
  /// line of height it takes is a line of the bill the shopkeeper cannot
  /// see. The button says what it does, so no heading is drawn over it.
  const AttachmentStrip.overPaper({super.key, required this.owner})
    : padding = const EdgeInsets.fromLTRB(
        BlTokens.space4,
        BlTokens.space2,
        BlTokens.space4,
        0,
      ),
      compact = true;

  final AttachmentOwner owner;
  final EdgeInsets padding;

  /// No heading: the add button and the photographs only.
  final bool compact;

  @override
  ConsumerState<AttachmentStrip> createState() => _AttachmentStripState();
}

class _AttachmentStripState extends ConsumerState<AttachmentStrip> {
  bool _busy = false;

  Future<void> _add(int held) async {
    // First statement, before any await: two taps in one frame both reach
    // here, and a disabled button only disables on the next build.
    if (_busy) return;
    final s = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (held >= EntryPhoto.maxPerEntry) {
      messenger.showSnackBar(
        SnackBar(content: Text(s.photoFull(EntryPhoto.maxPerEntry))),
      );
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(s.photoFromCamera),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(s.photoFromGallery),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    setState(() => _busy = true);
    final container = ProviderScope.containerOf(context, listen: false);
    final services = ref.read(appServicesProvider);
    try {
      final picker = ImagePicker();
      // A first pass in the plugin, so a 50-megapixel original never
      // reaches Dart whole on an Android Go handset; the services do the
      // real reduction and keep the ceiling.
      final picked = source == ImageSource.camera
          ? [
              ?await picker.pickImage(
                source: ImageSource.camera,
                maxWidth: 1600,
                maxHeight: 1600,
                imageQuality: 85,
              ),
            ]
          : await picker.pickMultiImage(
              maxWidth: 1600,
              maxHeight: 1600,
              imageQuality: 85,
              limit: EntryPhoto.maxPerEntry - held,
              requestFullMetadata: false,
            );
      for (final file in picked.take(EntryPhoto.maxPerEntry - held)) {
        await services.photos.add(
          ownerTable: widget.owner.table,
          ownerId: widget.owner.id,
          kind: widget.owner.kind,
          source: await file.readAsBytes(),
          fileName: file.name,
        );
      }
      container.bumpRefresh();
    } on FormatException {
      messenger.showSnackBar(SnackBar(content: Text(s.pictureNotAnImage)));
    } on PlatformException {
      // The camera refused: permission said no, or there is none.
      messenger.showSnackBar(SnackBar(content: Text(s.photoCameraRefused)));
    } on PhotoRefused catch (refused) {
      messenger.showSnackBar(SnackBar(content: Text(refused.reason)));
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('${s.commonSomethingWentWrong}: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open(List<EntryPhoto> photos, int index) => unawaited(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoViewerScreen(photos: photos, initialIndex: index),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    // A party's papers are not for every role; nothing is drawn at all for
    // one that may not see them, rather than a button that only says no.
    if (!ref.watch(appServicesProvider).photos.mayHandle(widget.owner.table)) {
      return const SizedBox.shrink();
    }
    final photos =
        ref.watch(entryPhotosProvider(widget.owner)).valueOrNull ??
        const <EntryPhoto>[];

    return Padding(
      padding: widget.padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.compact) ...[
            Text(
              photos.isEmpty
                  ? s.photoStripTitle
                  : '${s.photoStripTitle} · ${photos.length}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: t.inkMuted,
              ),
            ),
            // A CNIC copy is the one photograph here somebody would worry
            // about. Said where it is taken, not in a policy nobody reads.
            if (widget.owner.isPapers)
              Padding(
                padding: const EdgeInsets.only(top: BlTokens.space1),
                child: Text(
                  s.photoPapersNote,
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                ),
              ),
            const SizedBox(height: BlTokens.space2),
          ],
          Wrap(
            spacing: BlTokens.space2,
            runSpacing: BlTokens.space2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final (i, photo) in photos.indexed)
                _Thumb(
                  key: ValueKey('entry-photo-${photo.id}'),
                  photo: photo,
                  label: s.photoOpen(i + 1),
                  onTap: () => _open(photos, i),
                ),
              if (photos.length < EntryPhoto.maxPerEntry)
                BlButton(
                  label: s.photoAdd,
                  icon: Icons.add_a_photo_outlined,
                  kind: BlButtonKind.secondary,
                  busy: _busy,
                  onPressed: _busy
                      ? null
                      : () => unawaited(_add(photos.length)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A small square of one photograph, opened full size with a tap.
class _Thumb extends StatelessWidget {
  const _Thumb({
    super.key,
    required this.photo,
    required this.label,
    required this.onTap,
  });

  final EntryPhoto photo;
  final String label;
  final VoidCallback onTap;

  static const _size = 64.0;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: t.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(BlTokens.radiusMd),
          child: Container(
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              color: t.surface,
              border: Border.all(
                color: photo.fromEarlierEntry ? t.accent : t.line,
              ),
              borderRadius: BorderRadius.circular(BlTokens.radiusMd),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Decoded at thumbnail size: eight 1280-pixel photographs
                // decoded whole for a strip of squares is memory an Android
                // Go handset does not have.
                Image.memory(
                  photo.bytes,
                  fit: BoxFit.cover,
                  cacheWidth: 192,
                  gaplessPlayback: true,
                  excludeFromSemantics: true,
                ),
                if (photo.fromEarlierEntry)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Container(
                      margin: const EdgeInsets.all(2),
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: t.surface,
                        borderRadius: BorderRadius.circular(BlTokens.radiusSm),
                      ),
                      child: Icon(Icons.history, size: 14, color: t.accent),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A button that opens an entry's photographs in a sheet, for a page with
/// no room for the strip itself — a charge, whose page is a dialog.
class EntryPhotosButton extends ConsumerWidget {
  const EntryPhotosButton({super.key, required this.owner});

  final AttachmentOwner owner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final count =
        ref.watch(entryPhotosProvider(owner)).valueOrNull?.length ?? 0;
    return TextButton.icon(
      icon: const Icon(Icons.photo_library_outlined),
      label: Text(count == 0 ? s.photosButton : '${s.photosButton} · $count'),
      onPressed: () => unawaited(
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (context) => Padding(
            padding: EdgeInsets.fromLTRB(
              BlTokens.space4,
              BlTokens.space4,
              BlTokens.space4,
              MediaQuery.viewPaddingOf(context).bottom + BlTokens.space4,
            ),
            child: AttachmentStrip(owner: owner),
          ),
        ),
      ),
    );
  }
}
