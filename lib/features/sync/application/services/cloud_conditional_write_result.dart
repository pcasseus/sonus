enum CloudConditionalWriteOutcome { applied, replayed, conflict, notFound }

class CloudConditionalWriteResult {
  const CloudConditionalWriteResult({
    required this.outcome,
    required this.serverRevision,
  });

  final CloudConditionalWriteOutcome outcome;
  final int? serverRevision;

  factory CloudConditionalWriteResult.fromRpcRow(Map<String, dynamic> row) {
    final rawOutcome = row['outcome'];
    final rawRevision = row['server_revision'];

    if (rawOutcome is! String) {
      throw StateError('Invalid conditional-write outcome.');
    }

    final outcome = switch (rawOutcome) {
      'applied' => CloudConditionalWriteOutcome.applied,
      'replayed' => CloudConditionalWriteOutcome.replayed,
      'conflict' => CloudConditionalWriteOutcome.conflict,
      'not_found' => CloudConditionalWriteOutcome.notFound,
      _ => throw StateError('Unknown conditional-write outcome: $rawOutcome.'),
    };

    if (outcome == CloudConditionalWriteOutcome.notFound) {
      if (rawRevision != null) {
        throw StateError(
          'A not_found conditional write must not have a server revision.',
        );
      }

      return const CloudConditionalWriteResult(
        outcome: CloudConditionalWriteOutcome.notFound,
        serverRevision: null,
      );
    }

    if (rawRevision is! int || rawRevision < 1) {
      throw StateError(
        'Conditional-write result requires a valid server revision.',
      );
    }

    return CloudConditionalWriteResult(
      outcome: outcome,
      serverRevision: rawRevision,
    );
  }
}
