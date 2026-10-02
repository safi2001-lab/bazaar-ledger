import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../printing/printing_providers.dart';

/// The two pictures that go on a shop's bills (M51).
enum ShopPicture {
  /// The shop's logo, at the head of a PDF bill.
  logo,

  /// The payment QR the shop's own bank or wallet gave it — Raast,
  /// JazzCash, Easypaisa — at the foot of a PDF bill and, if the owner asks,
  /// the till roll.
  paymentQr,
}

/// One of the shop's bill pictures: what is there, and a way to change it.
///
/// Picked from the gallery, never the camera, for the reason the item
/// picture gives: on Android 13+ the system photo picker needs no
/// permission at all, so a shop adding its logo costs the Play listing
/// nothing. A QR is usually a screenshot from the wallet app anyway, or the
/// picture the bank sent.
///
/// Nothing here makes a QR. The one on the bill is the picture picked here,
/// reprinted; with no picture, the bill carries the alias and IBAN as text
/// and no QR at all.
class ShopPictureField extends ConsumerStatefulWidget {
  const ShopPictureField({super.key, required this.kind});

  final ShopPicture kind;

  @override
  ConsumerState<ShopPictureField> createState() => _ShopPictureFieldState();
}

class _ShopPictureFieldState extends ConsumerState<ShopPictureField> {
  bool _busy = false;

  FutureProvider<ImageAttachment?> get _provider =>
      widget.kind == ShopPicture.logo ? shopLogoProvider : paymentQrProvider;

  Future<void> _pick() async {
    // First statement, before any await: two taps in one frame both reach
    // here.
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final s = AppStrings.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        // A first pass in the plugin, so a 108-megapixel original never
        // reaches Dart whole on an Android Go handset. The real shrinking,
        // and the size ceiling, are the services'.
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked == null) return;
      final source = await picked.readAsBytes();
      final services = ref.read(appServicesProvider);
      if (widget.kind == ShopPicture.logo) {
        await services.setShopLogo(source, fileName: picked.name);
      } else {
        await services.setPaymentQr(source, fileName: picked.name);
      }
      container.bumpRefresh();
    } on FormatException {
      // A PDF picked by mistake, or a format this build cannot read. Said
      // in words, because "nothing happened" leaves a shopkeeper tapping
      // again.
      messenger.showSnackBar(SnackBar(content: Text(s.pictureNotAnImage)));
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('${s.commonSomethingWentWrong}: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    if (_busy) return;
    setState(() => _busy = true);
    final container = ProviderScope.containerOf(context, listen: false);
    final services = ref.read(appServicesProvider);
    try {
      if (widget.kind == ShopPicture.logo) {
        await services.clearShopLogo();
      } else {
        await services.clearPaymentQr();
      }
      container.bumpRefresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final bytes = ref.watch(_provider).valueOrNull?.bytes;
    final logo = widget.kind == ShopPicture.logo;

    return BlCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                ? Icon(
                    logo ? Icons.storefront_outlined : Icons.qr_code_2,
                    color: t.inkMuted,
                  )
                : Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    semanticLabel: logo
                        ? s.billDesignLogo
                        : s.billDesignPaymentQr,
                  ),
          ),
          const SizedBox(width: BlTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  logo ? s.billDesignLogo : s.billDesignPaymentQr,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: t.ink,
                  ),
                ),
                Text(
                  logo ? s.billDesignLogoHint : s.billDesignPaymentQrHint,
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                ),
                const SizedBox(height: BlTokens.space2),
                Wrap(
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
