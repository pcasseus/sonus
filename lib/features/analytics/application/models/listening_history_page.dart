import '../../domain/models/listening_history_cursor.dart';
import 'listening_history_entry.dart';

class ListeningHistoryPage {
  const ListeningHistoryPage({
    required this.entries,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<ListeningHistoryEntry> entries;
  final ListeningHistoryCursor? nextCursor;
  final bool hasMore;
}
