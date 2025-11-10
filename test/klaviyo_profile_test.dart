import 'package:flutter_test/flutter_test.dart';
import 'package:klaviyo_flutter/src/klaviyo_profile.dart';

void main() {
  group('KlaviyoProfile', () {
    test('toJson includes all populated fields', () {
      final profile = KlaviyoProfile(
        id: 'id-1',
        email: 'user@example.com',
        phoneNumber: '+123456789',
        firstName: 'First',
        lastName: 'Last',
        organization: 'Org',
        title: 'Title',
        image: 'https://example.com/avatar.png',
        address1: 'Line 1',
        address2: 'Line 2',
        city: 'City',
        country: 'Country',
        region: 'Region',
        zip: '12345',
        timezone: 'Europe/Tallinn',
        latitude: 10.0,
        longitude: -20.5,
        properties: {'tier': 'gold'},
      );

      expect(profile.toJson(), {
        'external_id': 'id-1',
        'email': 'user@example.com',
        'phone_number': '+123456789',
        'first_name': 'First',
        'last_name': 'Last',
        'organization': 'Org',
        'title': 'Title',
        'image': 'https://example.com/avatar.png',
        'address1': 'Line 1',
        'address2': 'Line 2',
        'city': 'City',
        'country': 'Country',
        'region': 'Region',
        'zip': '12345',
        'timezone': 'Europe/Tallinn',
        'latitude': 10.0,
        'longitude': -20.5,
        'properties': {'tier': 'gold'},
      });
    });

    test('fromJson mirrors toJson', () {
      final json = {
        'external_id': 'id-2',
        'email': 'friend@example.com',
        'city': 'Tallinn',
        'latitude': 1,
        'longitude': -1,
      };

      final profile = KlaviyoProfile.fromJson(json);
      expect(profile.id, 'id-2');
      expect(profile.email, 'friend@example.com');
      expect(profile.city, 'Tallinn');
      expect(profile.latitude, 1);
      expect(profile.longitude, -1);
    });

    test('copyWith overrides and clears values', () {
      final profile = KlaviyoProfile(
        email: 'first@example.com',
        city: 'Berlin',
        latitude: 1,
      );

      final updated = profile.copyWith(
        email: 'second@example.com',
        city: null,
        latitude: 2.5,
      );

      expect(updated.email, 'second@example.com');
      expect(updated.city, isNull);
      expect(updated.latitude, 2.5);
    });
  });
}
