import 'dart:typed_data';

import '../identity/actor_context.dart';

/// A picture the shop owns: an item photograph, a cheque, an imported bank QR.
///
/// Stored inline as bytes rather than as a path, and the schema says why: a
/// backup is then one file, and a restore cannot come back with every picture
/// missing because the phone it was taken on is gone. That only works if the
/// pictures stay small, which is what [ImageAttachment.maxBytes] is for.
final class ImageAttachment {
  const ImageAttachment({
    required this.id,
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
  });

  final String id;
  final Uint8List bytes;
  final String mimeType;
  final int width;
  final int height;

  /// The longest edge a stored picture may have.
  ///
  /// A shop item does not need a photograph anybody would print. It needs one
  /// a cashier can recognise on a 720x1600 screen at arm's length, and 512
  /// pixels is generous for that. The original from a phone camera is four
  /// thousand pixels wide and eight megabytes, which is a database nobody can
  /// back up over a shop's connection.
  static const maxEdge = 512;

  /// And a hard ceiling on the encoded result.
  ///
  /// Refused rather than stored, because a picture that slips through at a
  /// megabyte is not one bad row — it is a backup that quietly stopped being
  /// something a shopkeeper can send over WhatsApp.
  static const maxBytes = 96 * 1024;
}

/// Reduces a picture to something a shop's database can carry.
///
/// A port rather than a function because the work is platform-shaped: decoding
/// a JPEG is not something `pk_domain` may do, and this is the seam that keeps
/// the rule about it structural.
abstract interface class ImageShrinker {
  /// Returns [source] re-encoded no larger than [ImageAttachment.maxEdge] on
  /// its longest edge.
  ///
  /// Throws if the bytes are not an image this build can read. That is a thing
  /// to tell a shopkeeper about — "this file is not a picture" — rather than a
  /// silent failure that leaves them wondering why nothing appeared.
  Future<ImageAttachment> shrink(Uint8List source, {required String id});
}

/// Where pictures live.
abstract interface class AttachmentStore {
  /// Stores [image] and points [ownerTable]/[ownerId] at it.
  ///
  /// Replaces whatever was there: an item has one photograph, and a shopkeeper
  /// changing it means the old one is gone rather than accumulating.
  Future<String> attach(
    ActorContext actor, {
    required String kind,
    required String ownerTable,
    required String ownerId,
    required ImageAttachment image,
    required String fileName,
  });

  /// The picture for one row, or null.
  Future<ImageAttachment?> forOwner(
    String firmId,
    String ownerTable,
    String ownerId,
  );

  /// Forgets it. A tombstone, like every other deletion here.
  Future<void> detach(
    ActorContext actor, {
    required String ownerTable,
    required String ownerId,
  });
}
