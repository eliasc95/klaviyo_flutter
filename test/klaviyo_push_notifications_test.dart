import 'package:flutter_test/flutter_test.dart';
import 'package:klaviyo_flutter/push_utils.dart';

void main() {
  group('KlaviyoPushEvent', () {
    test('round-trips via map', () {
      final now = DateTime.now();
      final event = KlaviyoPushEvent(
        type: KlaviyoPushEventType.opened,
        appState: KlaviyoAppState.background,
        appStateOnReceive: KlaviyoAppState.foreground,
        didLaunchApp: true,
        notificationId: 'id-1',
        title: 'Hello',
        body: 'World',
        imageUrl: 'https://example.com/img.png',
        deepLink: 'app://example',
        actionId: 'reply',
        isSilentPush: false,
        timestamp: now,
        klaviyoCampaignId: 'cmp',
        klaviyoFlowId: 'flow',
        klaviyoMessageId: 'msg',
        rawData: {'k': 'v'},
      );

      final map = event.toMap();
      final parsed = KlaviyoPushEvent.fromMap(map);

      expect(parsed.type, event.type);
      expect(parsed.appState, event.appState);
      expect(parsed.appStateOnReceive, event.appStateOnReceive);
      expect(parsed.didLaunchApp, event.didLaunchApp);
      expect(parsed.notificationId, event.notificationId);
      expect(parsed.title, event.title);
      expect(parsed.body, event.body);
      expect(parsed.imageUrl, event.imageUrl);
      expect(parsed.deepLink, event.deepLink);
      expect(parsed.actionId, event.actionId);
      expect(parsed.isSilentPush, event.isSilentPush);
      expect(parsed.klaviyoCampaignId, event.klaviyoCampaignId);
      expect(parsed.klaviyoFlowId, event.klaviyoFlowId);
      expect(parsed.klaviyoMessageId, event.klaviyoMessageId);
      expect(parsed.rawData, event.rawData);
      expect(
        parsed.timestamp.millisecondsSinceEpoch,
        event.timestamp.millisecondsSinceEpoch,
      );
    });

    test('handles missing optional fields', () {
      final map = {
        'type': 'received',
        'appState': 'foreground',
        'timestamp': 123,
      };
      final event = KlaviyoPushEvent.fromMap(map);

      expect(event.type, KlaviyoPushEventType.received);
      expect(event.appState, KlaviyoAppState.foreground);
      expect(event.appStateOnReceive, isNull);
      expect(event.didLaunchApp, isFalse);
      expect(event.notificationId, isNull);
      expect(event.rawData, isEmpty);
    });
  });

  group('KlaviyoTokenEvent', () {
    test('constructs from map', () {
      final nowMs = 1700000000000;
      final event =
          KlaviyoTokenEvent.fromMap({'token': 'abc', 'timestamp': nowMs});

      expect(event.token, 'abc');
      expect(event.timestamp.millisecondsSinceEpoch, nowMs);
    });
  });
}
