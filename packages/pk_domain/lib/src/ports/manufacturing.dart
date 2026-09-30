import '../identity/actor_context.dart';
import '../manufacturing/assembly.dart';

/// A recipe, as the screens list it.
final class BomView {
  const BomView({
    required this.id,
    required this.draft,
    required this.outputName,
    required this.outputUnitCode,
    required this.componentNames,
  });

  final String id;
  final BomDraft draft;
  final String outputName;
  final String outputUnitCode;

  /// By component item id.
  final Map<String, String> componentNames;
}

/// What a production run posted.
final class AssemblyResult {
  const AssemblyResult({required this.assemblyNo, required this.plan});

  final String assemblyNo;
  final AssemblyPlan plan;
}

/// Writing recipes and production runs.
abstract interface class ManufacturingWriter {
  /// Saves a recipe, replacing [bomId]'s lines when it is given.
  Future<String> saveBom(ActorContext actor, BomDraft draft, {String? bomId});

  /// Makes [runs] batches of [bomId]: components off the shelf, the
  /// finished item on it, its average cost moved, and the work booked.
  Future<AssemblyResult> assemble(ActorContext actor, String bomId, int runs);
}
