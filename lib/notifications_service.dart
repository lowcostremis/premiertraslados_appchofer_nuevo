// lib/notifications_service.dart

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> initNotifications() async {
    // 1. Pedir permisos de notificación al usuario
    await _firebaseMessaging.requestPermission();

    // 2. Definir el canal de notificación para Android
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel', // ID del canal
      'Notificaciones de Viajes', // Nombre visible para el usuario
      description: 'Este canal se usa para notificaciones importantes de viajes.',
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('reserva_sound'), // ¡Aquí se define el sonido!
    );

    // 3. Crear el canal en el dispositivo
    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // 4. Inicializar el plugin de notificaciones locales
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
    await _flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  // Función para mostrar la notificación cuando la app está en primer plano
  void showNotification(RemoteMessage message) {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      _flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'high_importance_channel', // Debe ser el mismo ID del canal
            'Notificaciones de Viajes',
            channelDescription: 'Este canal se usa para notificaciones importantes de viajes.',
            importance: Importance.max,
            playSound: true,
            sound: RawResourceAndroidNotificationSound('reserva_sound'), // ¡Y aquí también!
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    }
  }
}