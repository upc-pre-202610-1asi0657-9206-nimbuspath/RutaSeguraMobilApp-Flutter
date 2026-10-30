import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `true` cada vez que el teléfono recupera alguna conexión (wifi o datos).
/// Es solo una pista para reintentar pronto: que haya red no garantiza que
/// el servidor responda.
final connectivityRestoredProvider = StreamProvider<bool>(
  (ref) => Connectivity().onConnectivityChanged.map(
        (r) => r.any((c) => c != ConnectivityResult.none),
      ),
);
