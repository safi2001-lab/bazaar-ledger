import 'dart:async';
import 'dart:io';

import 'package:pk_domain/pk_domain.dart';

/// A printer on the shop's own Wi-Fi, on the port every one of them uses.
///
/// Port 9100 is the raw-printing convention — no protocol, no handshake, no
/// driver: open a socket, write ESC/POS, close it. That is why this transport
/// needs no plugin at all, only `dart:io`, and why it is the one worth having
/// first. A USB-and-LAN printer costs about Rs 1,200 more than USB alone and
/// lets a counter and a back office share one machine.
///
/// Nothing here reaches the internet. The address is a private LAN IP, and
/// the app declares no INTERNET permission in release for exactly that
/// reason — a shopkeeper checking the Play listing should be able to see the
/// app cannot phone anywhere.
final class TcpPrinter implements PrinterTransport {
  const TcpPrinter({
    this.port = 9100,
    this.connectTimeout = const Duration(seconds: 4),
    this.writeTimeout = const Duration(seconds: 20),
  });

  final int port;
  final Duration connectTimeout;

  /// How long the whole job may take once connected.
  ///
  /// Generous, because a long bill on a slow thermal head genuinely takes
  /// seconds and cutting it off halfway is the one outcome worse than
  /// waiting: paper has already moved.
  final Duration writeTimeout;

  @override
  String get kind => 'tcp';

  @override
  Future<bool> get isAvailable async => true;

  /// Sweeps the device's own subnet for anything listening on the port.
  ///
  /// Deliberately a sweep rather than mDNS. Thermal printers in this price
  /// bracket mostly do not advertise themselves, and a shopkeeper who has
  /// just plugged one in cannot be asked for its IP address. Two hundred and
  /// fifty-four probes at a short timeout, in parallel, is a couple of
  /// seconds on a shop network.
  @override
  Future<List<PrinterTarget>> discover({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final prefixes = await _localSubnets();
    if (prefixes.isEmpty) return const [];

    final found = <PrinterTarget>[];
    // One subnet at a time. A device on both Wi-Fi and a hotspot would
    // otherwise fire five hundred sockets at once, which some Android ROMs
    // simply refuse.
    for (final prefix in prefixes) {
      final probes = <Future<void>>[];
      for (var host = 1; host < 255; host++) {
        final address = '$prefix.$host';
        probes.add(() async {
          try {
            final socket = await Socket.connect(
              address,
              port,
              timeout: timeout,
            );
            socket.destroy();
            found.add(
              PrinterTarget(
                kind: kind,
                address: '$address:$port',
                name: address,
                details: 'Port $port',
              ),
            );
          } on Object {
            // Nothing there. Which is true of almost every address on the
            // subnet, so this is the ordinary case and not worth recording.
          }
        }());
      }
      await Future.wait(probes);
    }

    found.sort((a, b) => a.address.compareTo(b.address));
    return found;
  }

  @override
  Future<void> send(PrinterTarget target, List<int> bytes) async {
    final (host, hostPort) = _split(target.address);
    Socket? socket;
    var written = 0;

    try {
      socket = await Socket.connect(host, hostPort, timeout: connectTimeout);
    } on Object catch (error) {
      // Nothing was sent, so this one is safe to try again on its own.
      throw PrinterException(
        'Could not reach the printer at $host: $error',
        target: target,
      );
    }

    try {
      // Written in chunks with the socket flushed between them, because a
      // thermal head is far slower than a network and several of the printers
      // this ships against have small input buffers. Handing them the whole
      // bill in one write is how a receipt comes out with the middle missing.
      const chunk = 1024;
      for (var offset = 0; offset < bytes.length; offset += chunk) {
        final end =
            offset + chunk < bytes.length ? offset + chunk : bytes.length;
        socket.add(bytes.sublist(offset, end));
        await socket.flush().timeout(writeTimeout);
        written = end;
      }
      // The close is part of the job. Some printers only begin cutting when
      // the connection ends, so returning before this would report a finished
      // print while the paper is still attached.
      await socket.flush().timeout(writeTimeout);
    } on Object catch (error) {
      throw PrinterException(
        'The printer stopped taking the receipt: $error',
        bytesWritten: written,
        target: target,
      );
    } finally {
      socket.destroy();
    }
  }

  static (String, int) _split(String address) {
    final at = address.lastIndexOf(':');
    if (at < 0) return (address, 9100);
    return (
      address.substring(0, at),
      int.tryParse(address.substring(at + 1)) ?? 9100,
    );
  }

  /// The `a.b.c` of every private IPv4 address this device holds.
  ///
  /// Private ranges only. Sweeping a public range would be scanning somebody
  /// else's network, which is both rude and the sort of thing that gets an
  /// app removed from a store.
  static Future<List<String>> _localSubnets() async {
    final prefixes = <String>{};
    try {
      for (final interface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      )) {
        for (final address in interface.addresses) {
          final parts = address.address.split('.');
          if (parts.length != 4) continue;
          final a = int.tryParse(parts[0]) ?? 0;
          final b = int.tryParse(parts[1]) ?? 0;
          final isPrivate = a == 10 ||
              (a == 172 && b >= 16 && b <= 31) ||
              (a == 192 && b == 168);
          if (isPrivate) prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
        }
      }
    } on Object {
      // No interfaces readable. The shopkeeper types the address instead.
    }
    return prefixes.toList();
  }
}
