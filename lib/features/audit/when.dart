import 'package:pk_bootstrap/pk_bootstrap.dart';

/// An instant as the shop reads it: its own date and time, in Pakistan.
String shopTime(int utcMillis) {
  final t = DateTime.fromMillisecondsSinceEpoch(
    utcMillis,
    isUtc: true,
  ).add(pakistanStandardTime);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}
