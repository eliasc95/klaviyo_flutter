# klaviyo_flutter

[![Pub](https://img.shields.io/pub/v/klaviyo_flutter.svg)](https://pub.dev/packages/klaviyo_flutter)
![CI](https://github.com/drybnikov/klaviyo_flutter/workflows/CI/badge.svg)
![](https://img.shields.io/coderabbit/prs/github/drybnikov/klaviyo_flutter?label=CodeRabbit)



Flutter wrapper for Klaviyo [Android](https://github.com/klaviyo/klaviyo-android-sdk),
and [iOS](https://github.com/klaviyo/klaviyo-swift-sdk) projects.

- Uses Klaviyo Android SDK Version `3.3.1`.
- The minimum Android SDK `minSdkVersion` required is 23.
- Uses Klaviyo iOS SDK Version `4.2.1`.
- The minimum iOS target version required is 13.

## Usage

Import `package:klaviyo_flutter/klaviyo_flutter.dart` and use the methods in `Klaviyo` class.

Example:

```dart
import 'package:flutter/material.dart';
import 'package:klaviyo_flutter/klaviyo_flutter.dart';

void main() async {
  // initialize the flutter binding.
  WidgetsFlutterBinding.ensureInitialized();
  // initialize the Klaviyo.
  // make sure to add key from your Klaviyo account public API.
  await Klaviyo.instance.initialize('apiKeyHere');
  runApp(App());
}

class App extends StatelessWidget {

  @override
  Widget build(BuildContext context) {
    return FlatButton(
      child: Text('Send Klaviyo SUCCESSFUL_PAYMENT event'),
      onPressed: () async {
        await Klaviyo.instance.logEvent(
          '\$successful_payment',
          {'\$value': 'paymentValue'},
        );
      },
    );
  }
}
```

See
Klaviyo [Android](https://help.klaviyo.com/hc/en-us/articles/14750928993307)
and [iOS](https://help.klaviyo.com/hc/en-us/articles/360023213971) package
documentation for more information.

### Updating profiles

Use `KlaviyoProfile` for bulk updates so you can send identifiers, standard
location fields, and custom properties in a single call. All fields are optional
and latitude/longitude are represented as doubles.

```dart
await Klaviyo.instance.updateProfile(
  KlaviyoProfile(
    id: 'customer-42',
    email: 'hey@example.com',
    phoneNumber: '+15555551212',
    city: 'Berlin',
    country: 'Germany',
    zip: '10117',
    timezone: 'Europe/Berlin',
    latitude: 52.520008,
    longitude: 13.404954,
    properties: {
      'app_version': '2.0.5',
    },
  ),
);
```

### Android

Permissions:
```xml
<uses-permission android:name="android.permission.INTERNET" />
```

Optional permissions:
```xml
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.VIBRATE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

Enable AndroidX + Jetifier support in your android/gradle.properties file (see example app):
```
android.useAndroidX=true
android.enableJetifier=true
```

### iOS

Make sure that you have a `NSPhotoLibraryUsageDescription` entry in your `Info.plist`.

```Info.plist
  <key>NSPhotoLibraryUsageDescription</key>
```  
```project.pbxproj 
  IPHONEOS_DEPLOYMENT_TARGET = 13.0;
```

### Push notifications setup

This plugin works alongside [`firebase_messaging`](https://pub.dev/packages/firebase_messaging)
to receive push notifications. Configure Firebase and each platform as follows.

#### Firebase prerequisites

- Create (or open) a Firebase project and add your Android/iOS apps.
- Download `google-services.json` and `GoogleService-Info.plist`.
- Enable Firebase Cloud Messaging and copy the server key. Add that key to the
  Klaviyo dashboard (**Account > Settings > Push**) so Klaviyo can deliver
  messages via FCM.

#### Android configuration

1. Place `google-services.json` inside `android/app/` and apply the Google
   services Gradle plugin per the Firebase docs.
2. Register `KlaviyoPushService` so Klaviyo can receive new tokens and payloads:

   ```xml
   <service
       android:name="com.klaviyo.pushFcm.KlaviyoPushService"
       android:exported="false">
     <intent-filter>
       <action android:name="com.google.firebase.MESSAGING_EVENT" />
     </intent-filter>
   </service>
   ```

3. (Optional) specify a default notification icon via

   ```xml
   <meta-data
       android:name="com.klaviyo.push.default_notification_icon"
       android:resource="@drawable/ic_notification" />
   ```

4. Forward the FCM token to Klaviyo:

   ```dart
   final token = await FirebaseMessaging.instance.getToken();
   if (token != null && token.isNotEmpty) {
     await Klaviyo.instance.sendTokenToKlaviyo(token);
   }
   ```

#### iOS configuration

1. Add `GoogleService-Info.plist` to the Runner target and enable Push
   Notifications + Background Modes (Remote notifications) in Xcode.
2. Register for APNs and forward the device token (converted to hex) through
   `Klaviyo.instance.sendTokenToKlaviyo`.
3. If you need to manipulate payloads or support rich media, add a Notification
   Service Extension and share an App Group with the main target.

#### Sending & tracking pushes

When users opt in, their tokens are synced to Klaviyo and can be targeted via
FCM/APNs. To record opens while the app is killed/backgrounded register the
Firebase background handler:

```dart
FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await Klaviyo.instance.handlePush(message.data);
}
```

Helpful references:

- [How to set up push notifications](https://help.klaviyo.com/hc/en-us/articles/360023213971)
- [How to send a push notification campaign](https://help.klaviyo.com/hc/en-us/articles/360006653972)
- [How to add a push notification to a flow](https://help.klaviyo.com/hc/en-us/articles/12932504108571)

> **Note:** `setBadgeCount` only affects iOS (where the Klaviyo SDK manages the
> application icon badge). On Android the method is a no-op because launcher
> badge behavior varies by device manufacturer.
