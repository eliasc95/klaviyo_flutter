import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Describes the type of push event that occurred.
enum KlaviyoPushEventType {
  received,
  opened,
  dismissed,
  actionTapped,
}

/// Describes the state of the app when the event was generated.
enum KlaviyoAppState {
  foreground,
  background,
  terminated,
}

@immutable
class KlaviyoPushEvent {
  const KlaviyoPushEvent({
    required this.type,
    required this.appState,
    this.appStateOnReceive,
    this.didLaunchApp = false,
    this.notificationId,
    this.title,
    this.body,
    this.imageUrl,
    this.deepLink,
    this.actionId,
    this.isSilentPush = false,
    required this.timestamp,
    this.klaviyoCampaignId,
    this.klaviyoFlowId,
    this.klaviyoMessageId,
    this.rawData = const {},
  });

  /// The type of push event.
  final KlaviyoPushEventType type;

  /// The app state when this event was triggered.
  final KlaviyoAppState appState;

  /// For 'opened' events: the app state when the notification was originally received.
  final KlaviyoAppState? appStateOnReceive;

  /// True if this event caused the app to launch from terminated state.
  final bool didLaunchApp;

  /// Unique identifier for this notification (platform-specific).
  final String? notificationId;

  /// Notification title.
  final String? title;

  /// Notification body text.
  final String? body;

  /// URL to notification image (if rich push).
  final String? imageUrl;

  /// Deep link URL extracted from the notification.
  final String? deepLink;

  /// The action identifier if user tapped an action button.
  final String? actionId;

  /// Whether this was a silent/data-only push.
  final bool isSilentPush;

  /// Timestamp when the event was processed.
  final DateTime timestamp;

  /// Klaviyo campaign ID (if present in payload).
  final String? klaviyoCampaignId;

  /// Klaviyo flow ID (if present in payload).
  final String? klaviyoFlowId;

  /// Klaviyo message ID (if present in payload).
  final String? klaviyoMessageId;

  /// Full raw payload data.
  final Map<String, dynamic> rawData;

  factory KlaviyoPushEvent.fromMap(Map<String, dynamic> map) {
    return KlaviyoPushEvent(
      type: KlaviyoPushEventType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => KlaviyoPushEventType.received,
      ),
      appState: KlaviyoAppState.values.firstWhere(
        (e) => e.name == map['appState'],
        orElse: () => KlaviyoAppState.foreground,
      ),
      appStateOnReceive: map['appStateOnReceive'] != null
          ? KlaviyoAppState.values.firstWhere(
              (e) => e.name == map['appStateOnReceive'],
              orElse: () => KlaviyoAppState.foreground,
            )
          : null,
      didLaunchApp: map['didLaunchApp'] == true,
      notificationId: map['notificationId'] as String?,
      title: map['title'] as String?,
      body: map['body'] as String?,
      imageUrl: map['imageUrl'] as String?,
      deepLink: map['deepLink'] as String?,
      actionId: map['actionId'] as String?,
      isSilentPush: map['isSilentPush'] == true,
      timestamp: map['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int)
          : DateTime.now(),
      klaviyoCampaignId: map['klaviyoCampaignId'] as String?,
      klaviyoFlowId: map['klaviyoFlowId'] as String?,
      klaviyoMessageId: map['klaviyoMessageId'] as String?,
      rawData: Map<String, dynamic>.from(map['rawData'] ?? const {}),
    );
  }

  /// Create a KlaviyoPushEvent from a Firebase RemoteMessage.
  factory KlaviyoPushEvent.fromRemoteMessage(
    RemoteMessage message, {
    required KlaviyoPushEventType type,
    required KlaviyoAppState appState,
    bool didLaunchApp = false,
  }) {
    final data = message.data;
    final notification = message.notification;
    final isSilent = notification == null && data.isNotEmpty;

    return KlaviyoPushEvent(
      type: type,
      appState: appState,
      didLaunchApp: didLaunchApp,
      notificationId: data['notification_id'] as String? ?? message.messageId,
      title: notification?.title ?? data['title'] as String?,
      body: notification?.body ?? data['body'] as String?,
      imageUrl: notification?.android?.imageUrl ??
          notification?.apple?.imageUrl ??
          data['image_url'] as String?,
      deepLink: data['deep_link'] as String? ?? data['url'] as String?,
      isSilentPush: isSilent,
      timestamp: message.sentTime ?? DateTime.now(),
      klaviyoCampaignId: data['_k.campaign_id'] as String? ??
          (data['_k'] is Map
              ? (data['_k'] as Map)['campaign_id'] as String?
              : null),
      klaviyoFlowId: data['_k.flow_id'] as String? ??
          (data['_k'] is Map
              ? (data['_k'] as Map)['flow_id'] as String?
              : null),
      klaviyoMessageId: data['_k.message_id'] as String? ??
          (data['_k'] is Map
              ? (data['_k'] as Map)['message_id'] as String?
              : null),
      rawData: data,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'appState': appState.name,
      'appStateOnReceive': appStateOnReceive?.name,
      'didLaunchApp': didLaunchApp,
      'notificationId': notificationId,
      'title': title,
      'body': body,
      'imageUrl': imageUrl,
      'deepLink': deepLink,
      'actionId': actionId,
      'isSilentPush': isSilentPush,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'klaviyoCampaignId': klaviyoCampaignId,
      'klaviyoFlowId': klaviyoFlowId,
      'klaviyoMessageId': klaviyoMessageId,
      'rawData': rawData,
    };
  }

  @override
  String toString() {
    return 'KlaviyoPushEvent(type: ${type.name}, appState: ${appState.name}, didLaunchApp: $didLaunchApp, title: $title)';
  }
}

@immutable
class KlaviyoTokenEvent {
  const KlaviyoTokenEvent({
    required this.token,
    required this.timestamp,
  });

  final String token;
  final DateTime timestamp;

  factory KlaviyoTokenEvent.fromMap(Map<String, dynamic> map) {
    return KlaviyoTokenEvent(
      token: map['token'] as String,
      timestamp: map['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int)
          : DateTime.now(),
    );
  }
}
