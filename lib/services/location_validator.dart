import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum TaskType { metro, bus, food, paper, rvm, clothing }

class ValidationResult {
  final bool isValid;
  final String? nearestName;
  final double? distanceMeters;

  ValidationResult({
    required this.isValid,
    this.nearestName,
    this.distanceMeters,
  });
}

class LocationValidator {
  static final Map<TaskType, Map<String, dynamic>> _cache = {};

  static Future<ValidationResult> validate(TaskType taskType) async {
    final position = await _getUserLocation();
    if (position == null) return ValidationResult(isValid: false);

    // مترو وباص ← من JSON
    if (taskType == TaskType.metro || taskType == TaskType.bus) {
      final assetPath = taskType == TaskType.metro
          ? 'assets/data/metro_stations.json'
          : 'assets/data/bus_stations.json';

      if (!_cache.containsKey(taskType)) {
        final raw = await rootBundle.loadString(assetPath);
        _cache[taskType] = json.decode(raw) as Map<String, dynamic>;
      }

      final data = _cache[taskType]!;
      final stations = data['stations'] as List<dynamic>;
      final radius = (data['validation_radius_meters'] as num).toDouble();

      double minDistance = double.infinity;
      String? nearestName;

      for (final station in stations) {
        final distance = Geolocator.distanceBetween(
          position.latitude, position.longitude,
          (station['lat'] as num).toDouble(),
          (station['lng'] as num).toDouble(),
        );
        if (distance < minDistance) {
          minDistance = distance;
          nearestName = station['name_ar'] as String?;
        }
      }

      return ValidationResult(
        isValid: minDistance <= radius,
        nearestName: nearestName,
        distanceMeters: minDistance,
      );
    }

    // الحاويات ← من Firestore
    final keyword = _firestoreKeyword(taskType);
    final snap = await FirebaseFirestore.instance
        .collection('facilities')
        .where('status', isEqualTo: 'نشط')
        .get();

    final docs = snap.docs.where((doc) {
      final type = (doc['type'] ?? '').toString().toLowerCase();
      return type.contains(keyword);
    }).toList();

    if (docs.isEmpty) return ValidationResult(isValid: false);

    double minDistance = double.infinity;
    String? nearestName;

    for (final doc in docs) {
      final distance = Geolocator.distanceBetween(
        position.latitude, position.longitude,
        (doc['lat'] as num).toDouble(),
        (doc['lng'] as num).toDouble(),
      );
      if (distance < minDistance) {
        minDistance = distance;
        nearestName = doc['type']?.toString();
      }
    }

    return ValidationResult(
      isValid: minDistance <= 100.0,
      nearestName: nearestName,
      distanceMeters: minDistance,
    );
  }

  static String _firestoreKeyword(TaskType type) {
    switch (type) {
      case TaskType.rvm:      return 'rvm';
      case TaskType.clothing: return 'ملابس';
      case TaskType.paper:    return 'ورق';
      case TaskType.food:     return 'طعام';
      default:                return '';
    }
  }

  static Future<Position?> _getUserLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    if (permission == LocationPermission.deniedForever) return null;

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }
}