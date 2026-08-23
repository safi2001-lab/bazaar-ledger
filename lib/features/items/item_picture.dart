import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// One item, one photograph.
///
/// Worth more here than in most catalogues. National literacy is around 60%
/// and rural literacy near 50%, so a cashier who cannot read a name fluently
/// can still recognise a packet — which is the same reason this product leads
/// with icons, big numerals and colour-coded direction everywhere else.
///
/// Gallery only, never the camera. Camera capture would pull in the CAMERA
/// permission, and that permission arrives with barcode scanning or not at
/// all. On Android 13+ this routes through the system Photo Picker, which
/// needs no permission whatsoever — so a shopkeeper photographing a tin of oil
/// costs the Play listing nothing.
class ItemPictureField extends ConsumerStatefulWidget {
  const ItemPictureField({super.key, required this.itemId});

  /// Null while an item is being created. A picture needs a row to hang off,
  /// so the field simply is not offered until the item has been saved once —
  /// which is honest, and better than accepting a photograph and losing it.
  final String? itemId;

  @override
  ConsumerState<ItemPictureField> createState() => _ItemPictureFieldState();
}

class _ItemPictureFieldState extends ConsumerState<ItemPictureField> {
  Uint8List? _bytes;
  bool _busy = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final itemId = widget.itemId;
    if (itemId == null) {
      setState(() => _loaded = true);
      return;
    }
    final services = ref.read(appServicesProvider);
    final firm = await ref.read(firmProvider.future);
    if (firm == null || !mounted) return;

    final picture = await services.pictures.itemPicture(firm.id, itemId);
    if (!mounted) return;
    setState(() {
      _bytes = picture?.bytes;
      _loaded = true;
    });
  }

  Future<void> _pick() async {
    // First statement, before any await. A disabled button only disables on
    // the next build, so two taps in one frame both reach here.
    if (_busy) return;
    final itemId = widget.itemId;
    if (itemId == null) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final s = AppStrings.of(context);

    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        // A first pass in the plugin, before the bytes ever reach Dart. The
        // shrinker does the real work and enforces the ceiling, but decoding
        // a 108-megapixel original on an Android Go handset is a stutter
        // worth avoiding — and some of these phones cannot hold one in memory
        // at all.
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked == null) {
        // Cancelled. Not an error, and not something to say anything about.
        if (mounted) setState(() => _busy = false);
        return;
      }

      final source = await picked.readAsBytes();
      final services = ref.read(appServicesProvider);
      await services.pictures.setItemPicture(
        services.actorNow(),
        itemId: itemId,
        source: source,
        fileName: picked.name,
      );
      ref.invalidate(refreshTickProvider);
      await _load();
      if (mounted) setState(() => _busy = false);
    } on FormatException {
      // A PDF picked by mistake, or a format this build cannot read. Said in
      // words, because "nothing happened" leaves a shopkeeper tapping again.
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(s.pictureNotAnImage)));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _remove() async {
    if (_busy) return;
    final itemId = widget.itemId;
    if (itemId == null) return;

    setState(() => _busy = true);
    final services = ref.read(appServicesProvider);
    await services.pictures.clearItemPicture(services.actorNow(), itemId);
    ref.invalidate(refreshTickProvider);
    if (!mounted) return;
    setState(() {
      _bytes = null;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;

    // Nothing at all until the item exists. A control that cannot work is
    // worse than an absent one: it teaches a shopkeeper that controls in this
    // app sometimes do nothing.
    if (widget.itemId == null || !_loaded) return const SizedBox.shrink();

    final bytes = _bytes;
    return Row(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: t.paper,
            border: Border.all(color: t.line),
            borderRadius: BorderRadius.circular(BlTokens.radiusMd),
          ),
          clipBehavior: Clip.antiAlias,
          child: bytes == null
              ? Icon(Icons.image_outlined, color: t.inkMuted)
              : Image.memory(bytes, fit: BoxFit.cover),
        ),
        const SizedBox(width: BlTokens.space3),
        Expanded(
          child: Wrap(
            spacing: BlTokens.space2,
            runSpacing: BlTokens.space2,
            children: [
              BlButton(
                label: bytes == null ? s.pictureAdd : s.pictureChange,
                icon: Icons.add_photo_alternate_outlined,
                kind: BlButtonKind.secondary,
                busy: _busy,
                onPressed: _busy ? null : _pick,
              ),
              if (bytes != null)
                BlButton(
                  label: s.pictureRemove,
                  icon: Icons.delete_outline,
                  kind: BlButtonKind.ghost,
                  onPressed: _busy ? null : _remove,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
