/// The result of a data-health check.
///
/// Returned rather than thrown: a shopkeeper who opens the app to a crash
/// screen has lost their business day, whereas one who is told the database
/// needs repairing still has a working restore button.
final class DatabaseHealth {
  const DatabaseHealth({required this.findings, required this.checkedAtUtc});

  final List<String> findings;
  final DateTime checkedAtUtc;

  bool get isHealthy => findings.isEmpty;

  @override
  String toString() => isHealthy
      ? 'DatabaseHealth(ok, checked $checkedAtUtc)'
      : 'DatabaseHealth(${findings.length} finding(s)): ${findings.join('; ')}';
}
