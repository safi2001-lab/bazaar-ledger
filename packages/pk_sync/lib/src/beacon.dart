import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Finding the master without typing its address (M23).
///
/// While it hosts, the master says where it is on the shop's wi-fi every
/// two seconds: one small UDP broadcast with the port it listens on and the
/// shop's name, and nothing else. A counter that is joining listens for a
/// few seconds and lists what it heard. It never leaves the wi-fi: a
/// broadcast does not cross a router.
///
/// Typing the address still works, for a network that drops broadcasts.
const beaconPort = 47471;

const _tag = 'BAZAAR-LEDGER/2';

/// A master heard on the wi-fi.
final class FoundMaster {
  const FoundMaster({
    required this.address,
    required this.port,
    required this.shopName,
  });

  final String address;
  final int port;
  final String shopName;

  /// What to type in the address box.
  String get hostAndPort => '$address:$port';
}

/// The master's side: says where it is until stopped.
final class SyncBeacon {
  SyncBeacon({
    this.every = const Duration(seconds: 2),
    InternetAddress? to,
    this.toPort = beaconPort,
  }) : _to = to ?? InternetAddress('255.255.255.255');

  final Duration every;
  final InternetAddress _to;
  final int toPort;

  RawDatagramSocket? _socket;
  Timer? _timer;

  bool get isRunning => _timer != null;

  Future<void> start({required int port, required String shopName}) async {
    if (isRunning) return;
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)
      ..broadcastEnabled = true;
    _socket = socket;
    final message = utf8.encode('$_tag $port ${shopName.trim()}');
    void say() {
      try {
        socket.send(message, _to, toPort);
      } on Object {
        // No wi-fi this second; the next tick tries again.
      }
    }

    say();
    _timer = Timer.periodic(every, (_) => say());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }
}

/// Listens for [listenFor] and returns every master heard, once each.
Future<List<FoundMaster>> findMasters({
  Duration listenFor = const Duration(seconds: 3),
  int port = beaconPort,
}) async {
  final RawDatagramSocket socket;
  try {
    socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: true,
    );
  } on SocketException {
    return const [];
  }
  final found = <String, FoundMaster>{};
  final sub = socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    final datagram = socket.receive();
    if (datagram == null) return;
    final String text;
    try {
      text = utf8.decode(datagram.data);
    } on FormatException {
      return;
    }
    final parts = text.split(' ');
    if (parts.length < 2 || parts.first != _tag) return;
    final masterPort = int.tryParse(parts[1]);
    if (masterPort == null) return;
    final master = FoundMaster(
      address: datagram.address.address,
      port: masterPort,
      shopName: parts.skip(2).join(' '),
    );
    found[master.hostAndPort] = master;
  });
  await Future<void>.delayed(listenFor);
  await sub.cancel();
  socket.close();
  return found.values.toList();
}
