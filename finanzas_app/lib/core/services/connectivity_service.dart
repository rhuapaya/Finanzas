import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Detecta cambios de conectividad para disparar la sincronización.
class ConnectivityService {
  ConnectivityService([Connectivity? connectivity]) : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  static bool _isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  Future<bool> isOnline() async {
    try {
      return _isOnline(await _connectivity.checkConnectivity());
    } catch (_) {
      return true; // Ante la duda, intentar.
    }
  }

  /// Emite `true` cada vez que el dispositivo recupera la conexión.
  Stream<bool> get onStatusChange =>
      _connectivity.onConnectivityChanged.map(_isOnline).distinct();
}
