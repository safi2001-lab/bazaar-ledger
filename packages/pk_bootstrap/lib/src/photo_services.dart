part of 'app_services.dart';

/// Photographs of the paper behind an entry (M60): the supplier's bill on a
/// purchase, the bijli bill on an expense, the deposit slip or the cheque on
/// a payment, the signed challan on a sale, the CNIC copy on a khata.
///
/// A seam over the attachment store, as [PictureServices] is for an item's
/// photograph, so no screen has to remember that a photograph is reduced
/// before it is kept, or what the ceiling is. The screen hands over what
/// the camera or the gallery gave it; what is kept is [EntryPhoto.maxEdge]
/// pixels and under [EntryPhoto.maxBytes].
///
/// ## Where they live
///
/// In the books, inline, so they go into every backup this phone makes and
/// come back with a restore. Not to other phones: pictures do not travel
/// over the shop's wi-fi (the sync store says why), so a parchi
/// photographed at the counter is on the counter's phone and in the
/// counter's backups. A CNIC copy, which is the sensitive one, therefore
/// never leaves the phone it was taken on except inside an encrypted backup
/// the owner makes.
///
/// ## Who may
///
/// Anybody signed in may add one to an entry: whoever can open an entry can
/// photograph the paper that goes with it, and adding evidence takes nothing
/// away. A customer's or supplier's papers are the exception both ways — a
/// CNIC copy is not something every counter boy should flick through — so
/// seeing, adding and taking those off take [Permission.correctEntries], as
/// taking any photograph off does: the owner, a manager or the accountant,
/// and with Data Lock on, a PIN as well (M42).
final class EntryPhotoServices {
  EntryPhotoServices._(this._app);

  final AppServices _app;

  DriftAttachments get _store =>
      DriftAttachments(_app.database, () => _app._runner);

  String get _firmId {
    final id = _app._identity;
    if (id == null) throw StateError('This device has no shop yet.');
    return id.firmId;
  }

  /// Whether whoever is signed in may see and add photographs on rows of
  /// [ownerTable].
  bool mayHandle(String ownerTable) =>
      ownerTable != 'parties' || _app.can(Permission.correctEntries);

  /// The photographs on one entry, oldest first, those carried from the
  /// entry it corrected among them. None at all for somebody who may not
  /// see a party's papers.
  Future<List<EntryPhoto>> of(String ownerTable, String ownerId) async {
    if (!mayHandle(ownerTable)) return const [];
    return _store.photosOf(_firmId, ownerTable, ownerId);
  }

  /// Reduces [source] and puts it on the entry, returning its id.
  ///
  /// Throws [FormatException] when the bytes are not a picture this build
  /// can read, and [PhotoRefused] when the entry is full or not in these
  /// books — both things to say to a shopkeeper in words.
  Future<String> add({
    required String ownerTable,
    required String ownerId,
    required EntryPhotoKind kind,
    required Uint8List source,
    required String fileName,
  }) async {
    if (!mayHandle(ownerTable)) _app.require(Permission.correctEntries);
    final actor = _app.actorNow();
    final prepared = preparePaperPhoto(source, id: ownerId);
    return _store.addPhoto(
      actor,
      kind: kind,
      ownerTable: ownerTable,
      ownerId: ownerId,
      image: prepared,
      fileName: fileName,
    );
  }

  /// Whether whoever is signed in may take a photograph off an entry.
  bool get mayRemove => _app.can(Permission.correctEntries);

  /// Takes a photograph off its entry, into the recycle bin.
  Future<void> remove(String photoId) async {
    _app.require(Permission.correctEntries);
    await _store.removePhoto(_app.actorNow(), photoId);
  }

  /// Every picture taken off and not yet brought back, the latest first —
  /// a party's papers only for whoever may see them.
  Future<List<RemovedPhoto>> removed() async => [
    for (final p in await _store.removedPhotos(_firmId))
      if (mayHandle(p.ownerTable)) p,
  ];

  /// Whether whoever is signed in may bring [photo] back: the shop's own
  /// pictures (the logo and the QR, M51) are the settings', everything
  /// else is putting an entry right.
  bool mayRestore(RemovedPhoto photo) => _app.can(_restoreNeeds(photo));

  /// Brings [photo] back onto what it was taken off.
  Future<void> restore(RemovedPhoto photo) async {
    _app.require(_restoreNeeds(photo));
    await _store.restorePhoto(_app.actorNow(), photo.id);
  }

  static Permission _restoreNeeds(RemovedPhoto photo) =>
      const {'firms', 'firm_payment_qr'}.contains(photo.ownerTable)
      ? Permission.settings
      : Permission.correctEntries;
}
