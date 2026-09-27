import 'listening_session_mutation_context.dart';

typedef ListeningSessionMutationAction<T> =
    Future<T> Function(ListeningSessionMutationContext context);

abstract interface class ListeningSessionMutationRunner {
  Future<T> run<T>(ListeningSessionMutationAction<T> action);
}
