import Flutter
import KlaviyoSwift
import UIKit
import UserNotifications

// swiftlint:disable identifier_name type_body_length file_length

/// A class that receives and handles calls from Flutter to complete the payment and push bridge.
public class KlaviyoFlutterPlugin: NSObject, FlutterPlugin,
    UNUserNotificationCenterDelegate, FlutterStreamHandler {
    private static let methodChannelName = "com.rightbite.denisr/klaviyo"
    private static let pushMethodChannelName = "com.rightbite.denisr/klaviyo_push"
    private static let pushEventChannelName = "com.rightbite.denisr/klaviyo_push_events"

    private let METHOD_UPDATE_PROFILE = "updateProfile"
    private let METHOD_INITIALIZE = "initialize"
    private let METHOD_SEND_TOKEN = "sendTokenToKlaviyo"
    private let METHOD_SET_BADGE_COUNT = "setBadgeCount"
    private let METHOD_LOG_EVENT = "logEvent"
    private let METHOD_HANDLE_PUSH = "handlePush"
    private let METHOD_SET_EXTERNAL_ID = "setExternalId"
    private let METHOD_GET_EXTERNAL_ID = "getExternalId"
    private let METHOD_RESET_PROFILE = "resetProfile"
    private let METHOD_SET_EMAIL = "setEmail"
    private let METHOD_GET_EMAIL = "getEmail"
    private let METHOD_SET_PHONE_NUMBER = "setPhoneNumber"
    private let METHOD_GET_PHONE_NUMBER = "getPhoneNumber"
    private let METHOD_SET_FIRST_NAME = "setFirstName"
    private let METHOD_SET_LAST_NAME = "setLastName"
    private let METHOD_SET_ORGANIZATION = "setOrganization"
    private let METHOD_SET_TITLE = "setTitle"
    private let METHOD_SET_IMAGE = "setImage"
    private let METHOD_SET_ADDRESS1 = "setAddress1"
    private let METHOD_SET_ADDRESS2 = "setAddress2"
    private let METHOD_SET_CITY = "setCity"
    private let METHOD_SET_COUNTRY = "setCountry"
    private let METHOD_SET_LATITUDE = "setLatitude"
    private let METHOD_SET_LONGITUDE = "setLongitude"
    private let METHOD_SET_REGION = "setRegion"
    private let METHOD_SET_ZIP = "setZip"
    private let METHOD_SET_TIMEZONE = "setTimezone"
    private let METHOD_SET_CUSTOM_ATTRIBUTE = "setCustomAttribute"

    private let klaviyo = KlaviyoSDK()

    private var pushMethodChannel: FlutterMethodChannel?
    private var pushEventSink: FlutterEventSink?
    private var initialNotification: [String: Any]?
    private var launchedFromNotification = false
    private var cachedPushToken: String?
    private var receiveStateByNotificationId: [String: String] = [:]
    private var pendingEvents: [[String: Any]] = []

    public static func register(with registrar: FlutterPluginRegistrar) {
        let messenger = registrar.messenger()
        let channel = FlutterMethodChannel(
            name: methodChannelName,
            binaryMessenger: messenger
        )
        let pushChannel = FlutterMethodChannel(
            name: pushMethodChannelName,
            binaryMessenger: messenger
        )
        let pushEvents = FlutterEventChannel(
            name: pushEventChannelName,
            binaryMessenger: messenger
        )
        let instance = KlaviyoFlutterPlugin()

        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.addMethodCallDelegate(instance, channel: pushChannel)
        pushEvents.setStreamHandler(instance)
        instance.pushMethodChannel = pushChannel
        registrar.addApplicationDelegate(instance)
    }

    // MARK: - UIApplicationDelegate

    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        if let notification = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            launchedFromNotification = true
            initialNotification = buildEventPayload(
                from: notification,
                type: "opened",
                appState: "terminated",
                didLaunchApp: true
            )
        }

        return true
    }

    public func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let isSilent = (userInfo["aps"] as? [String: Any])?["content-available"] as? Int == 1
        let appState = currentAppState()
        let event = buildEventPayload(
            from: userInfo,
            type: "received",
            appState: appState,
            didLaunchApp: false,
            isSilent: isSilent
        )
        if let notificationId = event["notificationId"] as? String {
            receiveStateByNotificationId[notificationId] = appState
        }
        sendPushEvent(event)
        completionHandler(.newData)
    }

    public func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        cachedPushToken = token

        // Auto-register token with Klaviyo
        klaviyo.set(pushToken: deviceToken)
        #if DEBUG
        print("[KlaviyoFlutter] Auto-registered push token with Klaviyo")
        #endif

        let tokenEvent: [String: Any] = [
            "token": token,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
        ]
        pushMethodChannel?.invokeMethod("onTokenRefresh", arguments: tokenEvent)
    }

    public func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if DEBUG
        print("[KlaviyoFlutter] Failed to register for remote notifications: \(error.localizedDescription)")
        #endif
    }

    // below method will be called when the user interacts with the push notification
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {

        // If this notification is Klaviyo's notification we'll handle it
        // else pass it on to the next push notification service to which it may belong
        let handled = KlaviyoSDK().handle(
            notificationResponse: response,
            withCompletionHandler: completionHandler
        )

        let userInfo = response.notification.request.content.userInfo
        var eventType = "opened"
        var actionId: String?

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            eventType = "opened"
        case UNNotificationDismissActionIdentifier:
            eventType = "dismissed"
        default:
            eventType = "actionTapped"
            actionId = response.actionIdentifier
        }

        let currentState = currentAppState()
        let notificationId = userInfo["notification_id"] as? String
        let appStateOnReceive = notificationId.flatMap { receiveStateByNotificationId[$0] }

        var event = buildEventPayload(
            from: userInfo,
            type: eventType,
            appState: currentState,
            didLaunchApp: launchedFromNotification,
            actionId: actionId
        )
        if let stateOnReceive = appStateOnReceive {
            event["appStateOnReceive"] = stateOnReceive
        }

        launchedFromNotification = false

        sendPushEvent(event)

        if !handled {
            completionHandler()
        }
    }

    // below method is called when the app receives push notifications when the app is the foreground
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (
            UNNotificationPresentationOptions
        ) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        let event = buildEventPayload(
            from: userInfo,
            type: "received",
            appState: "foreground",
            didLaunchApp: false
        )
        if let notificationId = event["notificationId"] as? String {
            receiveStateByNotificationId[notificationId] = "foreground"
        }
        sendPushEvent(event)

        var options: UNNotificationPresentationOptions = [.alert]
        if #available(iOS 14.0, *) {
            options = [.list, .banner]
        }
        completionHandler(options)
    }

    // swiftlint:disable function_body_length cyclomatic_complexity
    public func handle(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        func setProfileAttribute(
            key: Profile.ProfileKey,
            name: String,
            argumentKey: String
        ) {
            guard
                let arguments = call.arguments as? [String: Any],
                let stringValue = arguments[argumentKey] as? String
            else {
                return result(
                    FlutterError(
                        code: "invalid_args",
                        message: "\(name) must be a non-null String",
                        details: nil
                    )
                )
            }
            klaviyo.set(profileAttribute: key, value: stringValue)
            result("\(name) updated")
        }

        func setNumericProfileAttribute(
            call: FlutterMethodCall,
            key: Profile.ProfileKey,
            name: String,
            argumentKey: String,
            result: FlutterResult
        ) {
            guard
                let arguments = call.arguments as? [String: Any],
                let numericValue = extractDouble(arguments[argumentKey])
            else {
                return result(
                    FlutterError(
                        code: "invalid_args",
                        message: "\(name) must be a numeric value",
                        details: nil
                    )
                )
            }
            klaviyo.set(profileAttribute: key, value: numericValue)
            result("\(name) updated")
        }

        switch call.method {
        case "getInitialNotification":
            result(initialNotification)

        case "clearInitialNotification":
            initialNotification = nil
            result(nil)

        case "getToken":
            result(cachedPushToken)

        case METHOD_INITIALIZE:
            guard
                let arguments = call.arguments as? [String: Any],
                let apiKey = arguments["apiKey"] as? String
            else {
                return result(
                    FlutterError(
                        code: "invalid_args",
                        message: "API key must be provided",
                        details: nil
                    )
                )
            }
            klaviyo.initialize(with: apiKey)
            result("Klaviyo initialized")

        case METHOD_SEND_TOKEN:
            guard
                let arguments = call.arguments as? [String: Any],
                let tokenData = arguments["token"] as? String
            else {
                return result(
                    FlutterError(
                        code: "invalid_args",
                        message: "Token must be provided",
                        details: nil
                    )
                )
            }
            klaviyo.set(pushToken: Data(hexString: tokenData))
            result("Token sent to Klaviyo")

        case METHOD_SET_BADGE_COUNT:
            guard
                let arguments = call.arguments as? [String: Any],
                let count = arguments["count"] as? Int
            else {
                return result(
                    FlutterError(
                        code: "invalid_args",
                        message: "count must be an Int",
                        details: nil
                    )
                )
            }
            DispatchQueue.main.async {
                self.klaviyo.setBadgeCount(count)
                result("Badge count set")
            }

        case METHOD_UPDATE_PROFILE:
            guard
                let arguments = call.arguments as? [String: Any]
            else {
                return result(
                    FlutterError(
                        code: "invalid_args",
                        message: "Profile must be provided",
                        details: nil
                    )
                )
            }
            // parsing location
            let address1 = arguments["address1"] as? String
            let address2 = arguments["address2"] as? String
            let city = arguments["city"] as? String
            let country = arguments["country"] as? String
            let region = arguments["region"] as? String
            let zip = arguments["zip"] as? String
            let timezone = arguments["timezone"] as? String
            let latitude = extractDouble(arguments["latitude"])
            let longitude = extractDouble(arguments["longitude"])

            let hasLocationData = [
                address1,
                address2,
                city,
                country,
                region,
                zip,
                timezone
            ].contains { value in value != nil } || latitude != nil || longitude != nil

            let location = hasLocationData
                ? Profile.Location(
                    address1: address1,
                    address2: address2,
                    city: city,
                    country: country,
                    latitude: latitude,
                    longitude: longitude,
                    region: region,
                    zip: zip,
                    timezone: timezone
                )
                : nil

            let profile = Profile(
                email: arguments["email"] as? String,
                phoneNumber: arguments["phone_number"] as? String,
                externalId: arguments["external_id"] as? String,
                firstName: arguments["first_name"] as? String,
                lastName: arguments["last_name"] as? String,
                organization: arguments["organization"] as? String,
                title: arguments["title"] as? String,
                image: arguments["image"] as? String,
                location: location,
                properties: arguments["properties"] as? [String: Any]
            )
            klaviyo.set(profile: profile)
            result("Profile updated")

        case METHOD_LOG_EVENT:
            guard
                let arguments = call.arguments as? [String: Any],
                let eventName = arguments["name"] as? String
            else {
                return result(
                    FlutterError(
                        code: "invalid_args",
                        message: "Event name must be provided",
                        details: nil
                    )
                )
            }
            let event = Event(
                name: .customEvent(eventName),
                properties: arguments["metaData"] as? [String: Any]
            )

            klaviyo.create(event: event)
            result("Event: [\(event)] created")

        case METHOD_HANDLE_PUSH:
            guard
                let arguments = call.arguments as? [String: Any]
            else {
                return result(
                    FlutterError(
                        code: "invalid_args",
                        message: "Push message must be provided",
                        details: nil
                    )
                )
            }

            if let properties = arguments["message"] as? [String: Any],
                properties["_k"] != nil {
                klaviyo.create(
                    event: Event(
                        name: .customEvent("$opened_push"),
                        properties: properties
                    )
                )

                return result(true)
            }
            result(false)

        case METHOD_GET_EXTERNAL_ID:
            result(klaviyo.externalId)

        case METHOD_RESET_PROFILE:
            klaviyo.resetProfile()
            result(true)

        case METHOD_GET_EMAIL:
            result(klaviyo.email)

        case METHOD_GET_PHONE_NUMBER:
            result(klaviyo.phoneNumber)

        case METHOD_SET_EXTERNAL_ID:
            guard
                let arguments = call.arguments as? [String: Any],
                let externalId = arguments["id"] as? String
            else {
                return result(
                    FlutterError(
                        code: "invalid_args",
                        message: "External ID must be provided",
                        details: nil
                    )
                )
            }
            klaviyo.set(externalId: externalId)
            result("ID updated")

        case METHOD_SET_EMAIL:
            guard
                let arguments = call.arguments as? [String: Any],
                let email = arguments["email"] as? String
            else {
                return result(
                    FlutterError(
                        code: "invalid_args",
                        message: "Email must be provided",
                        details: nil
                    )
                )
            }

            klaviyo.set(email: email)
            result("Email updated")

        case METHOD_SET_PHONE_NUMBER:
            guard
                let arguments = call.arguments as? [String: Any],
                let phoneNumber = arguments["phoneNumber"] as? String
            else {
                return result(
                    FlutterError(
                        code: "invalid_args",
                        message: "Phone number must be provided",
                        details: nil
                    )
                )
            }

            klaviyo.set(phoneNumber: phoneNumber)
            result("Phone updated")

        case METHOD_SET_FIRST_NAME:
            setProfileAttribute(
                key: .firstName,
                name: "First name",
                argumentKey: "firstName"
            )

        case METHOD_SET_LAST_NAME:
            setProfileAttribute(
                key: .lastName,
                name: "Last name",
                argumentKey: "lastName"
            )

        case METHOD_SET_TITLE:
            setProfileAttribute(
                key: .title,
                name: "Title",
                argumentKey: "title"
            )

        case METHOD_SET_ORGANIZATION:
            setProfileAttribute(
                key: .organization,
                name: "Organization",
                argumentKey: "organization"
            )

        case METHOD_SET_IMAGE:
            setProfileAttribute(
                key: .image,
                name: "Image",
                argumentKey: "image"
            )

        case METHOD_SET_ADDRESS1:
            setProfileAttribute(
                key: .address1,
                name: "Address 1",
                argumentKey: "address"
            )

        case METHOD_SET_ADDRESS2:
            setProfileAttribute(
                key: .address2,
                name: "Address 2",
                argumentKey: "address"
            )

        case METHOD_SET_CITY:
            setProfileAttribute(key: .city, name: "City", argumentKey: "city")

        case METHOD_SET_COUNTRY:
            setProfileAttribute(
                key: .country,
                name: "Country",
                argumentKey: "country"
            )

        case METHOD_SET_LATITUDE:
            setNumericProfileAttribute(
                call: call,
                key: .latitude,
                name: "Latitude",
                argumentKey: "latitude",
                result: result
            )

        case METHOD_SET_LONGITUDE:
            setNumericProfileAttribute(
                call: call,
                key: .longitude,
                name: "Longitude",
                argumentKey: "longitude",
                result: result
            )

        case METHOD_SET_REGION:
            setProfileAttribute(
                key: .region,
                name: "Region",
                argumentKey: "region"
            )

        case METHOD_SET_ZIP:
            setProfileAttribute(key: .zip, name: "Zip", argumentKey: "zip")

        case METHOD_SET_TIMEZONE:
            // Klaviyo takes timezone from environment on iOS
            result("Success")

        case METHOD_SET_CUSTOM_ATTRIBUTE:
            guard
                let arguments = call.arguments as? [String: Any],
                let key = arguments["key"] as? String,
                let value = arguments["value"] as? String
            else {
                return result(
                    FlutterError(
                        code: "invalid_args",
                        message: "Method setCustomAttribute requires arguments {key: String, value: String}",
                        details: nil
                    )
                )
            }
            klaviyo.set(profileAttribute: .custom(customKey: key), value: value)
            result("Attribute \(key) updated")

        default:
            result(FlutterMethodNotImplemented)
        }
    }
    // swiftlint:enable function_body_length cyclomatic_complexity

    // MARK: - Push helpers

    private func currentAppState() -> String {
        switch UIApplication.shared.applicationState {
        case .active:
            return "foreground"
        case .inactive, .background:
            return "background"
        @unknown default:
            return "foreground"
        }
    }

    private func buildEventPayload(
        from userInfo: [AnyHashable: Any],
        type: String,
        appState: String,
        didLaunchApp: Bool,
        actionId: String? = nil,
        isSilent: Bool = false
    ) -> [String: Any] {
        let aps = userInfo["aps"] as? [String: Any]
        let alert = aps?["alert"]

        var title: String?
        var body: String?

        if let alertDict = alert as? [String: Any] {
            title = alertDict["title"] as? String
            body = alertDict["body"] as? String
        } else if let alertString = alert as? String {
            body = alertString
        }

        let klaviyoData = userInfo["_k"] as? [String: Any]

        return [
            "type": type,
            "appState": appState,
            "didLaunchApp": didLaunchApp,
            "notificationId": userInfo["notification_id"] as? String as Any,
            "title": title as Any,
            "body": body as Any,
            "imageUrl": userInfo["image_url"] as? String as Any,
            "deepLink": (userInfo["deep_link"] as? String ?? userInfo["url"] as? String) as Any,
            "actionId": actionId as Any,
            "isSilentPush": isSilent,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "klaviyoCampaignId": klaviyoData?["campaign_id"] as Any,
            "klaviyoFlowId": klaviyoData?["flow_id"] as Any,
            "klaviyoMessageId": klaviyoData?["message_id"] as Any,
            "rawData": convertToStringKeyedDict(userInfo),
        ]
    }

    private func convertToStringKeyedDict(_ dict: [AnyHashable: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in dict {
            guard let stringKey = key as? String else { continue }
            if let nestedDict = value as? [AnyHashable: Any] {
                result[stringKey] = convertToStringKeyedDict(nestedDict)
            } else {
                result[stringKey] = value
            }
        }
        return result
    }

    private func sendPushEvent(_ event: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let sink = self.pushEventSink {
                sink(event)
            } else {
                self.pendingEvents.append(event)
            }
        }
    }

    // MARK: - FlutterStreamHandler

    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        pushEventSink = events
        // Flush any pending events
        for event in pendingEvents {
            events(event)
        }
        pendingEvents.removeAll()
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        pushEventSink = nil
        return nil
    }
}

extension Data {
    init(hexString: String) {
        self =
            hexString
            .dropFirst(hexString.hasPrefix("0x") ? 2 : 0)
            .compactMap { $0.hexDigitValue.map { UInt8($0) } }
            .reduce(
                into: (
                    data: Data(capacity: hexString.count / 2),
                    byte: nil as UInt8?
                )
            ) { partialResult, nibble in
                if let pendingNibble = partialResult.byte {
                    partialResult.data.append(pendingNibble + nibble)
                    partialResult.byte = nil
                } else {
                    partialResult.byte = nibble << 4
                }
            }.data
    }
}

// swiftlint:enable identifier_name type_body_length

private func extractDouble(_ rawValue: Any?) -> Double? {
    if let value = rawValue as? Double {
        return value
    }
    if let numberValue = rawValue as? NSNumber {
        return numberValue.doubleValue
    }
    if let stringValue = rawValue as? String {
        return Double(stringValue)
    }
    return nil
}
