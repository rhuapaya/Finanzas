import 'dart:async';

/// Tablas que pueden cambiar.
enum ChangedTable { users, categories, transactions, budgets, recurring }

class DataChange {
  const DataChange(this.table, {this.fromSync = false});

  final ChangedTable table;

  /// `true` si el cambio proviene de datos descargados (no debe re-subirse).
  final bool fromSync;
}

/// Bus de eventos de cambios locales: refresca la UI y agenda la sincronización.
class DataChangeBus {
  final _controller = StreamController<DataChange>.broadcast();

  Stream<DataChange> get stream => _controller.stream;

  void emit(ChangedTable table, {bool fromSync = false}) {
    if (!_controller.isClosed) _controller.add(DataChange(table, fromSync: fromSync));
  }

  Future<void> dispose() => _controller.close();
}
