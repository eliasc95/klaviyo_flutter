library klaviyo_flutter;

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:klaviyo_flutter/push_utils.dart';
import 'package:klaviyo_flutter/src/klaviyo_flutter_platform_interface.dart';
import 'package:klaviyo_flutter/src/klaviyo_profile.dart';

export 'klaviyo_flutter.dart';
export 'src/klaviyo_profile.dart';

class Klaviyo {
  /// private constructor to not allow the object creation from outside.
  Klaviyo._();

  static final Klaviyo _instance = Klaviyo._();

  bool _initialized = false;

  /// get the instance of the [Klaviyo].
  static Klaviyo get instance => _instance;

  // Push notification channels
  static const MethodChannel _pushMethodChannel =
      MethodChannel('com.rightbite.denisr/klaviyo_push');
  static const EventChannel _pushEventChannel =
      EventChannel('com.rightbite.denisr/klaviyo_push_events');

  // Push notification state
  final StreamController<KlaviyoPushEvent> _pushEventController =
      StreamController<KlaviyoPushEvent>.broadcast();
  final StreamController<KlaviyoTokenEvent> _tokenEventController =
      StreamController<KlaviyoTokenEvent>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;
  StreamSubscription<RemoteMessage>? _fcmForegroundSub;
  StreamSubscription<RemoteMessage>? _fcmOpenedAppSub;
  StreamSubscription<String>? _fcmTokenSub;
  KlaviyoPushEvent? _androidInitialNotification;

  /// Function to initialize the Klaviyo SDK.
  ///
  /// First, you'll need to get your Klaviyo [apiKey] public API key for your Klaviyo account.
  ///
  /// You can get these from Klaviyo settings:
  /// * [public API key](https://www.klaviyo.com/settings/account/api-keys)
  ///
  /// Then, initialize Klaviyo in main method.
  Future<void> initialize(String apiKey) async {
    if (_initialized) return;

    if (apiKey.trim().isEmpty) {
      throw ArgumentError.value(apiKey, 'apiKey', 'must not be empty');
    }

    // Initialize the native Klaviyo SDK
    await KlaviyoFlutterPlatform.instance.initialize(apiKey);

    // Set up push notification handling
    await _initializePushNotifications();

    _initialized = true;
  }

  /// Set up push notification handling for both platforms.
  Future<void> _initializePushNotifications() async {
    // Set up method call handler for native callbacks
    _pushMethodChannel.setMethodCallHandler(_handleMethodCall);

    // iOS: Listen to native event channel for push events
    // Note: iOS native code already calls KlaviyoSDK().handle(notificationResponse:)
    // which tracks $opened_push events, so we do NOT call _trackPushOpened here
    // to avoid double-counting.
    if (!kIsWeb && Platform.isIOS) {
      _eventSubscription = _pushEventChannel
          .receiveBroadcastStream()
          .map((event) => KlaviyoPushEvent.fromMap(
              Map<String, dynamic>.from(event as Map<dynamic, dynamic>)))
          .listen(
        (event) {
          _pushEventController.add(event);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (kDebugMode) {
            developer.log(
              'Push event stream error: $error',
              name: 'Klaviyo',
              error: error,
              stackTrace: stackTrace,
            );
          }
        },
      );
    }

    // Android: Bridge Firebase Messaging streams
    if (!kIsWeb && Platform.isAndroid) {
      await _setupAndroidFirebaseMessaging();
    }
  }

  /// Set up Firebase Messaging listeners on Android.
  Future<void> _setupAndroidFirebaseMessaging() async {
    final messaging = FirebaseMessaging.instance;

    // Handle foreground messages
    _fcmForegroundSub = FirebaseMessaging.onMessage.listen((message) {
      if (kDebugMode) {
        developer.log(
          'Android: Foreground push received: ${message.notification?.title}',
          name: 'Klaviyo',
        );
      }
      final event = KlaviyoPushEvent.fromRemoteMessage(
        message,
        type: KlaviyoPushEventType.received,
        appState: KlaviyoAppState.foreground,
      );
      _pushEventController.add(event);
    });

    // Handle notification taps (app was in background)
    // Note: Android native code now calls Klaviyo.handlePush(intent) via ActivityAware,
    // which tracks $opened_push events, so we do NOT call _trackPushOpened here
    // to avoid double-counting.
    _fcmOpenedAppSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (kDebugMode) {
        developer.log(
          'Android: Push opened app: ${message.notification?.title}',
          name: 'Klaviyo',
        );
      }
      final event = KlaviyoPushEvent.fromRemoteMessage(
        message,
        type: KlaviyoPushEventType.opened,
        appState: KlaviyoAppState.background,
      );
      _pushEventController.add(event);
    });

    // Handle token refreshes - auto-register with Klaviyo
    _fcmTokenSub = messaging.onTokenRefresh.listen((token) async {
      if (kDebugMode) {
        final truncated =
            token.length >= 8 ? '${token.substring(0, 8)}...' : token;
        developer.log('Android: FCM token refreshed: $truncated',
            name: 'Klaviyo');
      }
      await sendTokenToKlaviyo(token);
      _tokenEventController.add(KlaviyoTokenEvent(
        token: token,
        timestamp: DateTime.now(),
      ));
    });

    // Get initial token and register with Klaviyo
    try {
      final initialToken = await messaging.getToken();
      if (initialToken != null) {
        if (kDebugMode) {
          final truncated = initialToken.length >= 8
              ? '${initialToken.substring(0, 8)}...'
              : initialToken;
          developer.log('Android: Initial FCM token: $truncated',
              name: 'Klaviyo');
        }
        await sendTokenToKlaviyo(initialToken);
      }
    } catch (e) {
      if (kDebugMode) {
        developer.log(
          'Android: Failed to get initial FCM token: $e',
          name: 'Klaviyo',
          error: e,
        );
      }
    }

    // Check for initial message (app launched from terminated state)
    // Note: Android native code handles tracking via Klaviyo.handlePush(intent)
    // in onAttachedToActivity, so we only emit to stream here for Flutter listeners.
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      if (kDebugMode) {
        developer.log(
          'Android: App launched from push: ${initialMessage.notification?.title}',
          name: 'Klaviyo',
        );
      }
      final event = KlaviyoPushEvent.fromRemoteMessage(
        initialMessage,
        type: KlaviyoPushEventType.opened,
        appState: KlaviyoAppState.terminated,
        didLaunchApp: true,
      );
      // Store for getInitialNotification() access
      _androidInitialNotification = event;
      // Emit to stream so listeners receive it
      _pushEventController.add(event);
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onTokenRefresh':
        final tokenEvent = KlaviyoTokenEvent.fromMap(
            Map<String, dynamic>.from(call.arguments));
        if (kDebugMode) {
          final truncatedToken = tokenEvent.token.length >= 8
              ? '${tokenEvent.token.substring(0, 8)}...'
              : tokenEvent.token;
          developer.log(
            'Push token auto-registered with Klaviyo: $truncatedToken',
            name: 'Klaviyo',
          );
        }
        _tokenEventController.add(tokenEvent);
        break;
    }
  }

  // ============================================================
  // Push Notification API
  // ============================================================

  /// Stream of all push notification events.
  Stream<KlaviyoPushEvent> get onPushEvent => _pushEventController.stream;

  /// Stream specifically for push received events.
  Stream<KlaviyoPushEvent> get onPushReceived =>
      onPushEvent.where((event) => event.type == KlaviyoPushEventType.received);

  /// Stream specifically for push opened events.
  Stream<KlaviyoPushEvent> get onPushOpened =>
      onPushEvent.where((event) => event.type == KlaviyoPushEventType.opened);

  /// Stream specifically for push dismissed events.
  Stream<KlaviyoPushEvent> get onPushDismissed => onPushEvent
      .where((event) => event.type == KlaviyoPushEventType.dismissed);

  /// Stream specifically for action button taps.
  Stream<KlaviyoPushEvent> get onPushActionTapped => onPushEvent
      .where((event) => event.type == KlaviyoPushEventType.actionTapped);

  /// Stream for token refresh events.
  Stream<KlaviyoTokenEvent> get onTokenRefresh => _tokenEventController.stream;

  /// Get the initial notification that launched the app (if any).
  ///
  /// On both iOS and Android, this returns the notification that launched the
  /// app from a terminated state. Call this after [initialize] to handle
  /// the cold-start case.
  Future<KlaviyoPushEvent?> getInitialNotification() async {
    if (!kIsWeb && Platform.isIOS) {
      final result = await _pushMethodChannel
          .invokeMethod<dynamic>('getInitialNotification');
      if (result == null) return null;
      return KlaviyoPushEvent.fromMap(Map<String, dynamic>.from(result));
    }
    if (!kIsWeb && Platform.isAndroid) {
      return _androidInitialNotification;
    }
    return null;
  }

  /// Clear the initial notification after handling.
  Future<void> clearInitialNotification() async {
    if (!kIsWeb && Platform.isIOS) {
      await _pushMethodChannel.invokeMethod('clearInitialNotification');
    }
    if (!kIsWeb && Platform.isAndroid) {
      _androidInitialNotification = null;
    }
  }

  /// Get the current push token.
  Future<String?> getPushToken() async {
    if (!kIsWeb && Platform.isAndroid) {
      return FirebaseMessaging.instance.getToken();
    }
    return _pushMethodChannel.invokeMethod<String>('getToken');
  }

  // ============================================================
  // Profile & Analytics API
  // ============================================================

  /// To log events in Klaviyo that record what users do in your app and when they do it.
  /// For example, you can record when user opened a specific screen in your app.
  /// You can also pass [metaData] about the event.
  Future<String> logEvent(String name, [Map<String, dynamic>? metaData]) {
    return KlaviyoFlutterPlatform.instance.logEvent(name, metaData);
  }

  /// The [token] to send to the Klaviyo to receive the notifications.
  ///
  /// For the Android, this [token] must be a FCM (Firebase cloud messaging) token.
  /// For the iOS, this [token] must be a APNS token.
  Future<void> sendTokenToKlaviyo(String token) {
    return KlaviyoFlutterPlatform.instance.sendTokenToKlaviyo(token);
  }

  /// Assign new identifiers and attributes to the currently tracked profile.
  /// If a profile has already been identified it will be overwritten by calling [resetProfile].
  ///
  /// The SDK keeps track of current profile details to
  /// build analytics requests with profile identifiers
  ///
  /// @param [profileMap] A map-like object representing properties of the new user
  /// @return Returns Future<String> success when called on Android or iOS
  ///
  /// All profile attributes recognized by the Klaviyo APIs [com.klaviyo.analytics.model.ProfileKey]
  Future<String> updateProfile(KlaviyoProfile profileModel) async {
    return KlaviyoFlutterPlatform.instance.updateProfile(profileModel);
  }

  /// Manually track a push notification open with Klaviyo.
  ///
  /// This creates a `$opened_push` event in Klaviyo. Usually this is called
  /// automatically when a push is opened, but you can call it manually if
  /// you have custom push handling.
  ///
  /// Returns `true` if the push was from Klaviyo and was tracked successfully.
  Future<bool> handlePush(Map<String, dynamic> message) {
    return KlaviyoFlutterPlatform.instance.handlePush(message);
  }

  /// Check if Klaviyo is already initialized.
  bool get isInitialized => _initialized;

  /// Check if the push [message] is from Klaviyo.
  bool isKlaviyoPush(Map<String, dynamic> message) => message.containsKey('_k');

  /// {@macro klaviyo_flutter_platform.setExternalId}
  Future<void> setExternalId(String id) =>
      KlaviyoFlutterPlatform.instance.setExternalId(id);

  /// @return The external ID of the currently tracked profile, if set
  Future<String?> getExternalId() =>
      KlaviyoFlutterPlatform.instance.getExternalId();

  /// Clear all stored profile identifiers and start a new tracked profile.
  ///
  /// NOTE: If a push token was registered to the current profile, you will
  /// need to call [sendTokenToKlaviyo] again to associate this device with
  /// a new profile.
  ///
  /// This should be called whenever an active user is removed (e.g. after logout).
  Future<void> resetProfile() => KlaviyoFlutterPlatform.instance.resetProfile();

  /// Assigns an email address to the currently tracked Klaviyo profile
  ///
  /// The SDK keeps track of current profile details to
  /// build analytics requests with profile identifiers
  ///
  /// This should be called whenever the active user in your app changes
  /// (e.g. after a fresh login)
  ///
  /// @param [email] Email address for active user
  Future<void> setEmail(String email) =>
      KlaviyoFlutterPlatform.instance.setEmail(email);

  /// @return The email of the currently tracked profile, if set
  Future<String?> getEmail() => KlaviyoFlutterPlatform.instance.getEmail();

  /// Assigns a phone number to the currently tracked Klaviyo profile
  ///
  /// NOTE: Phone number format is not validated, but should conform to Klaviyo formatting
  /// see (documentation)[https://help.klaviyo.com/hc/en-us/articles/360046055671-Accepted-phone-number-formats-for-SMS-in-Klaviyo]
  ///
  /// The SDK keeps track of current profile details to
  /// build analytics requests with profile identifiers
  ///
  /// This should be called whenever the active user in your app changes
  /// (e.g. after a fresh login)
  ///
  /// @param [phoneNumber] Phone number for active user
  Future<void> setPhoneNumber(String phoneNumber) =>
      KlaviyoFlutterPlatform.instance.setPhoneNumber(phoneNumber);

  /// @return The phone number of the currently tracked profile, if set
  Future<String?> getPhoneNumber() =>
      KlaviyoFlutterPlatform.instance.getPhoneNumber();

  /// {@macro klaviyo_flutter_platform.setFirstName}
  Future<void> setFirstName(String firstName) =>
      KlaviyoFlutterPlatform.instance.setFirstName(firstName);

  /// {@macro klaviyo_flutter_platform.setLastName}
  Future<void> setLastName(String lastName) =>
      KlaviyoFlutterPlatform.instance.setLastName(lastName);

  /// {@macro klaviyo_flutter_platform.setOrganization}
  Future<void> setOrganization(String organization) =>
      KlaviyoFlutterPlatform.instance.setOrganization(organization);

  /// {@macro klaviyo_flutter_platform.setTitle}
  Future<void> setTitle(String title) =>
      KlaviyoFlutterPlatform.instance.setTitle(title);

  /// {@macro klaviyo_flutter_platform.setImage}
  Future<void> setImage(String image) =>
      KlaviyoFlutterPlatform.instance.setImage(image);

  /// {@macro klaviyo_flutter_platform.setAddress1}
  Future<void> setAddress1(String address) =>
      KlaviyoFlutterPlatform.instance.setAddress1(address);

  /// {@macro klaviyo_flutter_platform.setAddress2}
  Future<void> setAddress2(String address) =>
      KlaviyoFlutterPlatform.instance.setAddress2(address);

  /// {@macro klaviyo_flutter_platform.setCity}
  Future<void> setCity(String city) =>
      KlaviyoFlutterPlatform.instance.setCity(city);

  /// {@macro klaviyo_flutter_platform.setCountry}
  Future<void> setCountry(String country) =>
      KlaviyoFlutterPlatform.instance.setCountry(country);

  /// {@macro klaviyo_flutter_platform.setLatitude}
  Future<void> setLatitude(double latitude) =>
      KlaviyoFlutterPlatform.instance.setLatitude(latitude);

  /// {@macro klaviyo_flutter_platform.setLongitude}
  Future<void> setLongitude(double longitude) =>
      KlaviyoFlutterPlatform.instance.setLongitude(longitude);

  /// {@macro klaviyo_flutter_platform.setRegion}
  Future<void> setRegion(String region) =>
      KlaviyoFlutterPlatform.instance.setRegion(region);

  /// {@macro klaviyo_flutter_platform.setZip}
  Future<void> setZip(String zip) =>
      KlaviyoFlutterPlatform.instance.setZip(zip);

  /// {@macro klaviyo_flutter_platform.setTimezone}
  Future<void> setTimezone(String timezone) =>
      KlaviyoFlutterPlatform.instance.setTimezone(timezone);

  /// {@macro klaviyo_flutter_platform.setCustomAttribute}
  Future<void> setCustomAttribute(String key, String value) =>
      KlaviyoFlutterPlatform.instance.setCustomAttribute(key, value);

  /// {@macro klaviyo_flutter_platform.setBadgeCount}
  Future<void> setBadgeCount(int count) =>
      KlaviyoFlutterPlatform.instance.setBadgeCount(count);

  /// Dispose resources. Call this when the app is shutting down.
  void dispose() {
    _eventSubscription?.cancel();
    _fcmForegroundSub?.cancel();
    _fcmOpenedAppSub?.cancel();
    _fcmTokenSub?.cancel();
    _pushEventController.close();
    _tokenEventController.close();
  }

  @visibleForTesting
  void debugReset() {
    _initialized = false;
  }
}
