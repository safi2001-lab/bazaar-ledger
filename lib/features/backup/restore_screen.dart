import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// Bringing a backup back.
///
/// No Riverpod, no services. The screen that needs this most is the one
/// shown when the database would not open at all, and there is nothing above
/// it to read a provider from. Everything it needs is handed in.
///
/// Three steps, and the books on this phone are untouched until the last:
/// pick a file (its date shows before anything is asked), open it with the
/// passphrase (what is inside is read out of the database it holds — the
/// shop's name, how many bills), and only then confirm. The confirm stages
/// the file; the swap happens when the app reopens, before anything can be
/// holding the database.
class RestoreScreen extends StatefulWidget {
  const RestoreScreen({
    super.key,
    required this.pickFile,
    required this.databasePath,
    required this.onRestored,
  });

  /// The system file picker, or a stand-in for it.
  final Future<Uint8List?> Function() pickFile;

  /// Where the books live, resolved when the restore is staged.
  final Future<String> Function() databasePath;

  /// Reopens the app, which is when a staged restore is swapped in.
  final Future<void> Function() onRestored;

  @override
  State<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends State<RestoreScreen> {
  final _passphrase = TextEditingController();

  Uint8List? _file;
  BackupHeader? _header;
  RestoreCandidate? _candidate;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await widget.pickFile();
      if (!mounted || bytes == null) return;
      // The header first, without the passphrase: a shopkeeper with three
      // backups on their Drive wants to know they picked the right one
      // before they type anything.
      final header = const BackupArchive().readHeader(bytes);
      setState(() {
        _file = bytes;
        _header = header;
        _candidate = null;
      });
    } on BackupRefused catch (refused) {
      if (mounted) setState(() => _error = refused.reason);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open() async {
    final file = _file;
    if (_busy || file == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final scratch = Directory(
        '${(await getTemporaryDirectory()).path}'
        '${Platform.pathSeparator}restore',
      );
      final candidate = await Restore.inspect(
        file,
        passphrase: _passphrase.text,
        scratch: scratch,
      );
      if (mounted) setState(() => _candidate = candidate);
    } on BackupRefused catch (refused) {
      if (mounted) setState(() => _error = refused.reason);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final candidate = _candidate;
    if (_busy || candidate == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Restore.stage(candidate, databasePath: await widget.databasePath());
      await widget.onRestored();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final header = _header;
    final candidate = _candidate;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.restoreTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BlTokens.space4),
          children: [
            BlButton(
              label: s.restorePick,
              icon: Icons.folder_open_outlined,
              kind: header == null
                  ? BlButtonKind.primary
                  : BlButtonKind.secondary,
              busy: _busy && header == null,
              onPressed: _busy ? null : () => unawaited(_pick()),
            ),
            if (header != null) ...[
              const SizedBox(height: BlTokens.space3),
              Text(
                s.restoreMadeOn(_localDate(header.createdAtUtc)),
                style: TextStyle(fontSize: 14, color: t.inkMuted),
              ),
            ],
            if (header != null && candidate == null) ...[
              const SizedBox(height: BlTokens.space4),
              BlField(
                controller: _passphrase,
                label: s.backupPassphrase,
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: BlTokens.space3),
              BlButton(
                label: s.restoreOpen,
                icon: Icons.lock_open_outlined,
                busy: _busy,
                onPressed: _busy ? null : () => unawaited(_open()),
              ),
            ],
            if (candidate != null) ...[
              const SizedBox(height: BlTokens.space4),
              BlCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.restoreFound,
                      style: TextStyle(fontSize: 13, color: t.inkMuted),
                    ),
                    const SizedBox(height: BlTokens.space1),
                    Text(
                      candidate.shopName,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: t.ink,
                      ),
                    ),
                    const SizedBox(height: BlTokens.space2),
                    Text(
                      s.restoreCounts(
                        '${candidate.bills}',
                        '${candidate.parties}',
                        '${candidate.items}',
                      ),
                      style: TextStyle(fontSize: 14, color: t.ink),
                    ),
                    if (candidate.lastEntryDateLocal != null)
                      Text(
                        s.restoreLastEntry(candidate.lastEntryDateLocal!),
                        style: TextStyle(fontSize: 13, color: t.inkMuted),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: BlTokens.space3),
              BlOfflineNote(message: s.restoreWarning),
              const SizedBox(height: BlTokens.space4),
              BlButton(
                label: _busy ? s.restoreRestarting : s.restoreConfirm,
                icon: Icons.settings_backup_restore,
                big: true,
                busy: _busy,
                onPressed: _busy ? null : () => unawaited(_confirm()),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: BlTokens.space3),
              Text(_error!, style: TextStyle(color: t.danger, fontSize: 14)),
            ],
          ],
        ),
      ),
    );
  }

  /// `YYYY-MM-DD HH:MM` in Pakistan time, which is where every shop using
  /// this is. The date a shopkeeper remembers making a backup is a local one.
  static String _localDate(DateTime utc) {
    final pkt = utc.toUtc().add(const Duration(hours: 5));
    final iso = pkt.toIso8601String();
    return '${iso.substring(0, 10)} ${iso.substring(11, 16)}';
  }
}
