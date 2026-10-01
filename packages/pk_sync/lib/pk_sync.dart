/// LAN multi-counter sync: what travels, how two peers trade it, and the
/// HTTP host and client that carry it over the shop's own wi-fi.
library;

export 'src/beacon.dart';
export 'src/exchange.dart';
export 'src/http_client.dart';
export 'src/http_host.dart';
export 'src/peer.dart';
export 'src/seal.dart' show WireSeal, defaultJoinWork;
