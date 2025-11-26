import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class Permissions {

  static Future<bool> checkPermissions(BuildContext context) async {
    // Berechtigung für Benachrichtigungen prüfen
    PermissionStatus notificationStatus = await Permission.notification.status;
    if (notificationStatus == PermissionStatus.denied && Platform.isAndroid) {
      notificationStatus = await Permission.notification.request();
    }

    // Wenn die Berechtigung permanent verweigert wurde, muss dies in den Einstellungen geändert werden.
    if ((notificationStatus.isPermanentlyDenied || notificationStatus.isDenied) && Platform.isAndroid) {
      if (!context.mounted) return false;
      showNotificationPermissionDeniedDialog(context);
      return false;
    }

    // Berechtigung für Standort prüfen
    LocationPermission locationStatus = await Geolocator.checkPermission();
    if (locationStatus == LocationPermission.denied) {
      locationStatus = await Geolocator.requestPermission();
    }

    // Wenn die Berechtigung permanent verweigert wurde, muss dies in den Einstellungen geändert werden.
    if (locationStatus == LocationPermission.denied ||
        locationStatus == LocationPermission.deniedForever ||
        locationStatus == LocationPermission.whileInUse) {
      if (!context.mounted) return false;
      showLocationPermissionDeniedDialog(context);
      return false;
    }

    return true; // alles erteilt
  }

  static void showNotificationPermissionDeniedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text("Benachrichtigungsberechtigung erforderlich"),
        content: Text(
            "Bitte erlauben Sie der App in den Einstellungen, Benachrichtigungen zu senden."),
        actions: [
          TextButton(
            onPressed: () {
              openAppSettings();
              Navigator.of(context).pop();
            },
            child: Text("Einstellungen"),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Permissions.closeApp();
            },
            child: Text("Schließen"),
          ),
        ],
      ),
    );
  }

  static void showLocationPermissionDeniedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text("Standortberechtigung erforderlich"),
        content: Text(
            "Bitte erlauben Sie der App den Standortzugriff 'Immer', um die Funktionalität im Hintergrund zu ermöglichen."),
        actions: [
          TextButton(
            onPressed: () {
              Geolocator.openAppSettings();
              Navigator.of(context).pop();
            },
            child: Text("Einstellungen"),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Permissions.closeApp();
            },
            child: Text("Schließen"),
          ),
        ],
      ),
    );
  }

  static void closeApp() {
    if (Platform.isAndroid) {
      SystemNavigator.pop();
    } else if (Platform.isIOS) {
      exit(0);
    }
  }
}
