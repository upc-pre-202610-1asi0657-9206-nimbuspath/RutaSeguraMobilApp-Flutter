class DriverNotification {
  const DriverNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.occurredAt,
    this.tripId,
    this.readAt,
  });

  final String id, title, body, category;
  final String? tripId;
  final DateTime occurredAt;
  final DateTime? readAt;

  factory DriverNotification.fromJson(Map<String, dynamic> json) =>
      DriverNotification(
        id: json['id'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        category: json['category'] as String,
        occurredAt: DateTime.parse(json['occurredAt'] as String),
        tripId: json['tripId'] as String?,
        readAt: json['readAt'] == null
            ? null
            : DateTime.parse(json['readAt'] as String),
      );
}

class DriverNotificationPage {
  const DriverNotificationPage(this.items, this.nextCursor);
  final List<DriverNotification> items;
  final String? nextCursor;
}
