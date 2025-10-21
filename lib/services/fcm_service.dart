// lib/services/fcm_service.dart
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

class FCMService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// 🔔 طلب الإذن للإشعارات + طباعة الحالة
  static Future<void> requestPermissionAndSaveToken() async {
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    print('🔔 حالة الإذن: ${settings.authorizationStatus}');
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      await _saveDeviceToken();
    }
  }

  /// 💾 حفظ الـ Token في Firestore داخل users/{uid}
  static Future<void> _saveDeviceToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await _messaging.getToken();
      if (token != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'fcmToken': token,
        }, SetOptions(merge: true));
        print('✅ تم حفظ توكن الإشعار: $token');
      }
    } catch (e) {
      print('❌ خطأ أثناء حفظ الـ token: $e');
    }
  }

  /// 📬 الاستماع للإشعارات وقت عمل التطبيق
  static void listenToForegroundMessages() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📩 إشعار وصلك أثناء الاستخدام!');
      print('العنوان: ${message.notification?.title}');
      print('المحتوى: ${message.notification?.body}');
    });
  }

  /// 🚀 إرسال الإشعار عبر خادم Node.js المحلي
  static Future<void> sendPushNotification({
    required String token,
    required String title,
    required String body,
  }) async {
    final url = Uri.parse(
      'http://10.0.2.2:3000/send-notification',
    ); // Emulator only
    final payload = {'token': token, 'title': title, 'body': body};

    try {
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (res.statusCode == 200) {
        print('✅ تم إرسال الإشعار بنجاح عبر السيرفر');
      } else {
        print('❌ فشل إرسال الإشعار: ${res.statusCode}');
        print('الرد: ${res.body}');
      }
    } catch (e) {
      print('⚠️ خطأ أثناء الاتصال بالسيرفر: $e');
    }
  }
}
