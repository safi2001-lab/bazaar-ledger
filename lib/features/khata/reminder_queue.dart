import 'dart:convert';

import 'package:pk_bootstrap/pk_bootstrap.dart';

/// The evening's round of reminders, one customer after another (M39).
///
/// Forty names, each a WhatsApp chat opened with the message typed, each
/// needing the shopkeeper to press Send and come back. That is twenty
/// minutes of switching between two apps on a phone whose ROM force-stops
/// whatever is in the background, so the round is kept on the phone after
/// every step: who is in it, who has been sent to, who was skipped. Killed
/// half way, the app opens the chase list offering to carry on from the
/// next name, not from the first.
///
/// Kept in the draft store, beside the half-rung bill, and not in the
/// books: a round is a scrap of paper under the till. What the books keep
/// is each reminder actually sent, in the khata's log, the moment the
/// shopkeeper says it went.
final class ReminderRound {
  ReminderRound({
    required this.firmId,
    required this.items,
    this.channel = ReminderChannel.whatsapp,
  });

  /// The firm the round was started in. A round from another firm's books
  /// on the same phone is not offered.
  final String firmId;

  /// WhatsApp, or the phone's own messages.
  ReminderChannel channel;

  final List<RoundItem> items;

  /// The first customer not yet sent to or skipped, or null when done.
  int? get current {
    for (var i = 0; i < items.length; i++) {
      if (items[i].status == RoundStatus.waiting) return i;
    }
    return null;
  }

  bool get isDone => current == null;
  int get sent => items.where((i) => i.status == RoundStatus.sent).length;
  int get skipped => items.where((i) => i.status == RoundStatus.skipped).length;
  int get left => items.where((i) => i.status == RoundStatus.waiting).length;

  String encode() => jsonEncode({
    'firm_id': firmId,
    'channel': channel.name,
    'items': [
      for (final i in items)
        {'party_id': i.partyId, 'name': i.name, 'status': i.status.name},
    ],
  });

  /// [text] as written by [encode], or null when it is not one.
  static ReminderRound? decode(String? text) {
    if (text == null) return null;
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, Object?>) return null;
      final items = json['items'];
      if (items is! List<Object?>) return null;
      return ReminderRound(
        firmId: json['firm_id'] as String? ?? '',
        channel: ReminderChannel.parse(json['channel'] as String?),
        items: [
          for (final i in items.whereType<Map<String, Object?>>())
            RoundItem(
              partyId: i['party_id'] as String? ?? '',
              name: i['name'] as String? ?? '',
              status: RoundStatus.values.firstWhere(
                (s) => s.name == i['status'],
                orElse: () => RoundStatus.waiting,
              ),
            ),
        ],
      );
    } on FormatException {
      // A scrap that cannot be read is a scrap that is not there.
      return null;
    }
  }

  /// The slot in the draft store.
  static const slot = 'reminder_round';

  /// The round left on this phone for [firmId], if one is unfinished.
  static Future<ReminderRound?> load(DraftStore drafts, String firmId) async {
    final round = decode(await drafts.read(slot));
    if (round == null || round.firmId != firmId || round.isDone) return null;
    return round;
  }

  Future<void> save(DraftStore drafts) => drafts.write(slot, encode());

  static Future<void> clear(DraftStore drafts) => drafts.clear(slot);
}

/// Where one customer in a round stands.
enum RoundStatus { waiting, sent, skipped }

final class RoundItem {
  RoundItem({
    required this.partyId,
    required this.name,
    this.status = RoundStatus.waiting,
  });

  final String partyId;
  final String name;
  RoundStatus status;
}
