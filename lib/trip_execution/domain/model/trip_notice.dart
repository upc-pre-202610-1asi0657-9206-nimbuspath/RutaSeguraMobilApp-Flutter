/// Avisos que la empresa provoca mientras el conductor está en un viaje.
library;

enum TripNoticeKind {
  /// La empresa canceló el viaje: ya no se puede operar.
  tripCancelled,

  /// La empresa cerró el SOS: ya se puede finalizar el viaje.
  sosResolved,
}

class TripNotice {
  const TripNotice(this.kind, {this.reason});

  final TripNoticeKind kind;

  /// Motivo de la cancelación, si el servidor lo informó.
  final String? reason;

  String get message => switch (kind) {
        TripNoticeKind.tripCancelled => reason == null || reason!.trim().isEmpty
            ? 'Tu empresa canceló este viaje.'
            : 'Tu empresa canceló este viaje.\nMotivo: ${reason!.trim()}',
        TripNoticeKind.sosResolved =>
          'Tu empresa resolvió el SOS. Ya puedes finalizar el viaje.',
      };
}
