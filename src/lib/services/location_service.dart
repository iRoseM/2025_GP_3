// lib/services/location_service.dart
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LocationService {
  // طلب إذن الموقع
  static Future<bool> requestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  // الحصول على الموقع الحالي
  static Future<GeoPoint?> getCurrentLocation() async {
    bool hasPermission = await requestPermission();
    if (!hasPermission) return null;

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: 100, // تحديث كل 100 متر
        ),
      );

      return GeoPoint(position.latitude, position.longitude);
    } catch (e) {
      print('❌ Error getting location: $e');
      return null;
    }
  }

  // حفظ الموقع في Firestore
  static Future<void> saveUserLocation(String userId, GeoPoint location) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'lastLocation': location,
        'lastLocationUpdatedAt': FieldValue.serverTimestamp(),
      });
      print('✅ Location saved for user: $userId');
    } catch (e) {
      print('⚠️ Could not save location: $e');
    }
  }

  // تحديث الموقع (يُستدعى عند فتح التطبيق أو كل فترة)
  static Future<void> updateUserLocation(String userId) async {
    GeoPoint? location = await getCurrentLocation();
    if (location != null) {
      await saveUserLocation(userId, location);
    }
  }
}
