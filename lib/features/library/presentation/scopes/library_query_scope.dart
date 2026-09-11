import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../../core/database/app_database.dart';
import '../../application/repositories/library_query_repository.dart';
import '../../data/daos/library_query_dao.dart';
import '../../data/repositories/sqlite_library_query_repository.dart';

class LibraryQueryScope extends StatefulWidget {
  const LibraryQueryScope({super.key, required this.child, this.database});

  final Widget child;
  final AppDatabase? database;

  @override
  State<LibraryQueryScope> createState() => _LibraryQueryScopeState();
}

class _LibraryQueryScopeState extends State<LibraryQueryScope> {
  late final AppDatabase _database;
  late final bool _ownsDatabase;

  LibraryQueryRepository? _repository;

  @override
  void initState() {
    super.initState();

    _ownsDatabase = widget.database == null;
    _database = widget.database ?? AppDatabase();

    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final database = await _database.database;

    final repository = SqliteLibraryQueryRepository(LibraryQueryDao(database));

    if (!mounted) {
      return;
    }

    setState(() {
      _repository = repository;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Provider<LibraryQueryRepository?>.value(
      value: _repository,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    if (_ownsDatabase) {
      unawaited(_database.close());
    }

    super.dispose();
  }
}
