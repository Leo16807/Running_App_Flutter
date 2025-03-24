import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';
import 'dart:async';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';


class LatLngTween extends Tween<LatLng> {
  LatLngTween({required LatLng begin, required LatLng end})
      : super(begin: begin, end: end);

  @override
  LatLng lerp(double t) {
    double lat = begin!.latitude + (end!.latitude - begin!.latitude) * t;
    double lon = begin!.longitude + (end!.longitude - begin!.longitude) * t;
    return LatLng(lat, lon);
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  MapScreenState createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> {
  // Variablen
  final Logger _logger = Logger();

  final MapController _mapController = MapController();
  LatLng _currentLocation = LatLng(0, 0);
  LatLng _startPosition = LatLng(0, 0);
  StreamSubscription<Position>? _positionStreamSubscription;

  bool _isFirstLocationUpdate = true;
  bool _runActive = false;
  bool _runPaused = false;

  var _activityType = "Laufen";
  double _kcalPerKm = 0;
  double _kcal = 0;

  Timer? _timer;
  Timer? _calculationTimer;
  Duration _elapsedTime = Duration.zero;
  final List<LatLng> _runPath = [];
  double _totalDistance = 0.0;
  double _totalDistanceInkm = 0.0;
  double _recentDistance = 0.0;
  double _averagePace = 0;
  double _averageSpeed = 0;
  double _currentPace = 0;
  double _currentSpeed = 0;

  //Funktionen
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkPermissions();
    });
  }

  Future<void> checkPermissions() async {
    PermissionStatus status = await Permission.notification.status;
    if (status == PermissionStatus.denied && Platform.isAndroid) {
      status = await Permission.notification.request();
      if (status == PermissionStatus.denied) {
        status = await Permission.notification.request();
      }
    }
    if (status.isPermanentlyDenied && Platform.isAndroid) {
      showNotificationPermissionDeniedDialog();
    }
    else {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever || permission == LocationPermission.whileInUse) {
        showLocationPermissionDeniedDialog();
      }
      else {
        startLocationUpdates();
      }
    }
  }

  void showNotificationPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Benachrichtigungsberechtigung erforderlich"),
          content: Text("Bitte erlauben Sie der App in den Einstellungen, Benachrichtigungen zu senden."),
          actions: <Widget>[
            TextButton(
              child: Text("Einstellungen"),
              onPressed: () {
                openAppSettings();
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text("Schließen"),
              onPressed: () {
                Navigator.of(context).pop();
                closeApp();
              },
            ),
          ],
        );
      },
    );
  }

  void showLocationPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Standortberechtigung erforderlich"),
          content: Text("Bitte erlauben Sie der App den Standortzugriff 'Immer', um die Funktionalität im Hintergrund zu ermöglichen."),
          actions: <Widget>[
            TextButton(
              child: Text("Einstellungen"),
              onPressed: () {
                Geolocator.openAppSettings();
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text("Schließen"),
              onPressed: () {
                Navigator.of(context).pop();
                closeApp();
              },
            ),
          ],
        );
      },
    );
  }

  void closeApp() {
    if (Platform.isAndroid) {
      SystemNavigator.pop();
    } else if (Platform.isIOS) {
      exit(0);
    }
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _calculationTimer?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  String formatDuration(Duration duration) {
    int hours = duration.inHours;
    int minutes = duration.inMinutes.remainder(60);
    int seconds = duration.inSeconds.remainder(60);

    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  String formatPace(double paceInSecondsPerKm) {
    if (paceInSecondsPerKm.isNaN || paceInSecondsPerKm.isInfinite || paceInSecondsPerKm <= 0) {
      return "00:00 min/km";
    }
    int minutes = (paceInSecondsPerKm ~/ 60);
    int seconds = (paceInSecondsPerKm % 60).toInt();

    return "$minutes:${seconds.toString().padLeft(2, '0')} min/km";
  }



  IconData getActivityIcon() {
    switch (_activityType) {
      case "Gehen":
        return Icons.directions_walk;
      case "Laufen":
        return Icons.directions_run;
      case "Fahrrad fahren":
        return Icons.pedal_bike;
      default:
        return Icons.help_outline;
    }
  }

  Future<void> startLocationUpdates() async {
    LocationPermission permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: Platform.isAndroid
            ? AndroidSettings(
            foregroundNotificationConfig:
            const ForegroundNotificationConfig(
              notificationTitle: "Standortverfolgung im Hintergrund",
              notificationText: "Dein Standort wird auch im Hintergrund verfolgt.",
              enableWakeLock: true,
            ),
            distanceFilter: 16,
            accuracy: LocationAccuracy.bestForNavigation,
        )

            : AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          activityType: ActivityType.fitness,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
          allowBackgroundLocationUpdates: true,
          distanceFilter: 16,
        ),
      ).listen((Position position) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });

        if (_runActive && !_runPaused) {
          if (_runPath.isEmpty || _runPath.last != _currentLocation) {
            _runPath.add(_currentLocation);
            calculateDistance();
          }
        }

        if (_isFirstLocationUpdate) {
          zoomToCurrentLocation();
          _isFirstLocationUpdate = false;
        }
      });

    } else {
      _logger.e('Standortberechtigung nicht erteilt');
      showLocationPermissionDeniedDialog();
    }
  }

  void zoomToCurrentLocation() {
    _mapController.move(_currentLocation, 16.0);
    _mapController.rotate(0);
  }

  void startRun() {
    _runPath.clear();
    _totalDistance = 0.0;
    _recentDistance = 0.0;
    _elapsedTime = Duration.zero;
    _startPosition = _currentLocation;
    _runPath.add(_startPosition);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _elapsedTime += const Duration(seconds: 1);
      });
    });

    _calculationTimer?.cancel();
    _calculationTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      calculateStats();
      _logger.d("Berechnung der Stats nach 10 Sekunden");
    });
  }

  void stopRun() {
    _timer?.cancel();
    _calculationTimer?.cancel();
    _elapsedTime = Duration.zero;

    _logger.d('Lauf beendet. Gesamtdistanz: ${_totalDistance.toStringAsFixed(2)} m');

    setState(() {
      _runPath.clear();
      _elapsedTime = Duration.zero;
      _totalDistance = 0.0;
      _totalDistanceInkm = 0.0;
      _averageSpeed = 0.0;
      _averagePace = 0.0;
      _currentPace = 0.0;
      _currentSpeed = 0.0;
      _kcal = 0.0;
      _startPosition = LatLng(0, 0);
    });
  }

  void pauseRun() {
    _timer?.cancel();
    _calculationTimer?.cancel();
  }

  void continueRun() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _elapsedTime += const Duration(seconds: 1);
      });
    });

    _calculationTimer?.cancel();
    _calculationTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      calculateStats();
    });
  }

  void calculateDistance() {
    if (_runPath.length > 1) {
      LatLng lastPoint = _runPath[_runPath.length - 2];
      LatLng currentPoint = _runPath.last;

      double distanceDelta = Geolocator.distanceBetween(
        lastPoint.latitude,
        lastPoint.longitude,
        currentPoint.latitude,
        currentPoint.longitude,
      );

      double distanceDeltaRounded = double.parse(distanceDelta.toStringAsFixed(2));

      _totalDistance += distanceDeltaRounded;
      _recentDistance += distanceDeltaRounded;
    }

    setState(() {
      _totalDistanceInkm = _totalDistance / 1000;
    });
  }

  void calculateStats() {
    // Durchschnittswerte basierend auf _totalDistance
    if (_totalDistance > 0) {
      _averagePace = (_elapsedTime.inSeconds) / (_totalDistance / 1000.0);
      _averageSpeed = (_totalDistance / 1000) / (_elapsedTime.inSeconds / 3600);
    } else {
      _averagePace = 0.0;
      _averageSpeed = 0.0;
    }

    // Momentanwerte basierend auf _recentDistance (letzte 10 Sekunden)
    if (_recentDistance > 0) {
      _currentPace = 10 / (_recentDistance / 1000.0);
      _currentSpeed = (_recentDistance / 1000) / (10 / 3600);
    } else {
      _currentPace = 0.0;
      _currentSpeed = 0.0;
    }

    // Kalorien berechnen
    if (_activityType == 'Gehen') {
      _kcalPerKm = 48;
    } else if (_activityType == 'Laufen') {
      _kcalPerKm = 80;
    } else if (_activityType == 'Fahrrad fahren') {
      _kcalPerKm = 32;
    }

    setState(() {
      if (_averagePace <= 6000) {
        _averagePace = _averagePace;
        _averageSpeed = _averageSpeed;
      } else {
        _averagePace = 0;
        _averageSpeed = 0;
      }

      if (_currentPace <= 6000) {
        _currentPace = _currentPace;
        _currentSpeed = _currentSpeed;
      } else {
        _currentPace = 0;
        _currentSpeed = 0;
      }

      _kcal = _kcalPerKm * _totalDistanceInkm;
    });

    _logger.d("Letzte 10 Sekunden Distanz: $_recentDistance m");
    _logger.d("Gesamtdistanz: $_totalDistance m");

    _recentDistance = 0.0;
  }

  void showPopUpMenu(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Aktivität beendet!"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Zeit:  ${formatDuration(_elapsedTime)}",
                    style: TextStyle(color: Colors.black, fontSize: 16),
                  ),
                  Text(
                    "Distanz: ${_totalDistanceInkm.toStringAsFixed(2)} km",
                    style: TextStyle(color: Colors.black, fontSize: 16),
                  ),
                  Text(
                    "⌀Pace:  ${formatPace(_averagePace)}",
                    style: TextStyle(color: Colors.black, fontSize: 16),
                  ),
                  Text(
                    "⌀Geschwindigkeit:  ${_averageSpeed.toStringAsFixed(1)} km/h",
                    style: TextStyle(color: Colors.black, fontSize: 16),
                  ),
                  Text(
                    "Verbrannte Kalorien:  ${_kcal.toStringAsFixed(0)} kcal",
                    style: TextStyle(color: Colors.black, fontSize: 16),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    stopRun();
                  },
                  child: Text("Schließen", style: TextStyle(color: Colors.black, fontSize: 16)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text("Running App"),
          centerTitle: true,
        ),
        body:
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _currentLocation,
            initialZoom: 16.0,
          ),
          children: [
            TileLayer(
              urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
            ),
            if (_runPath.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _runPath,
                    strokeWidth: 4.0,
                    color: Colors.blue,
                  ),
                ],
              ),
            if (_runPath.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _runPath,
                    strokeWidth: 4.0,
                    color: Colors.blue,
                  ),
                ],
              ),

            if (_runActive)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _startPosition,
                    radius: 5,
                    color: Colors.green,
                    borderColor: Colors.white,
                    borderStrokeWidth: 5,
                    useRadiusInMeter: false,
                  ),
                ],
              ),
            TweenAnimationBuilder<LatLng>(
              tween: LatLngTween(begin: _currentLocation, end: _currentLocation),
              duration: Duration(seconds: 1),
              builder: (context, LatLng location, child) {
                return CircleLayer(
                  circles: [
                    CircleMarker(
                      point: location,
                      color: Colors.blue,
                      borderColor: Colors.white,
                      borderStrokeWidth: 5,
                      useRadiusInMeter: false,
                      radius: 5,
                    ),
                  ],
                );
              },
            ),
            if (_runActive)
              Container(
                  margin: const EdgeInsets.fromLTRB(0, 0, 0, 510),
                  color: Color(0x99000000),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 10, left: 24),
                        child: Text(
                            "Aktivität: $_activityType",
                            style: TextStyle(color: Colors.white, fontSize: 16)
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 10, left: 10),
                                child: Text(
                                  "Zeit:  ${formatDuration(_elapsedTime)}",
                                  style: TextStyle(color: Colors.white, fontSize: 16),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 10, left: 10),
                                child: Text(
                                  "⌀Pace:  ${formatPace(_averagePace)}",
                                  style: TextStyle(color: Colors.white, fontSize: 16),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 10, left: 10),
                                child: Text(
                                  "Pace:  ${formatPace(_currentPace)}",
                                  style: TextStyle(color: Colors.white, fontSize: 16),
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 10, right: 20),
                                child: Text(
                                  "Distanz: ${_totalDistanceInkm.toStringAsFixed(2)} km",
                                  style: TextStyle(color: Colors.white, fontSize: 16),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 10, right: 20),
                                child: Text(
                                  "⌀Speed: ${_averageSpeed.toStringAsFixed(1)} km/h",
                                  style: TextStyle(color: Colors.white, fontSize: 16),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 10, right: 20),
                                child: Text(
                                  "Speed:  ${_currentSpeed.toStringAsFixed(1)} km/h",
                                  style: TextStyle(color: Colors.white, fontSize: 16),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Padding(
                          padding: const EdgeInsets.only(top: 10, left: 24),
                          child: Text(
                            "Verbrauchte Kalorien:  ${_kcal.toStringAsFixed(0)} kcal",
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          )
                      ),
                    ],
                  )
              )
          ],
        ),

        floatingActionButton: Stack(
          children: [
            Positioned(
              right: 16,
              bottom: 128,
              child: FloatingActionButton(
                onPressed: zoomToCurrentLocation,
                shape: CircleBorder(),
                backgroundColor: Color(0xFF5CD2ED),
                child: Icon(Icons.my_location, color: Colors.black),
              ),
            ), // Button zentrieren

            if (!_runActive)
              Positioned(
                left: 64,
                bottom: 16,
                width: 48,
                height: 48,
                child: SpeedDial(
                  icon: getActivityIcon(),
                  backgroundColor: Colors.white,
                  iconTheme: IconThemeData(color: Colors.black),
                  spacing: 12,
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(
                      color: Colors.black,
                      width: 2.0,
                    ),
                  ),
                  children: [
                    SpeedDialChild(
                      child: Icon(Icons.directions_walk, color: Colors.black),
                      backgroundColor: Colors.white,
                      onTap: () {
                        setState(() {
                          _activityType = "Gehen";
                        });
                      },
                    ),
                    SpeedDialChild(
                      child: Icon(Icons.directions_run, color: Colors.black),
                      backgroundColor: Colors.white,
                      onTap: () {
                        setState(() {
                          _activityType = "Laufen";
                        });
                      },
                    ),
                    SpeedDialChild(
                      child: Icon(Icons.pedal_bike, color: Colors.black),
                      backgroundColor: Colors.white,
                      onTap: () {
                        setState(() {
                          _activityType = "Fahrrad fahren";
                        });
                      },
                    ),
                  ],
                ),
              ), // Button zum Wählen der Sportart

            if (!_runActive)
              Positioned(
                left: (MediaQuery.of(context).size.width - 96) / 2,
                bottom: 16,
                width: 128,
                height: 48,
                child: FloatingActionButton(
                  onPressed: () {
                    setState(() {
                      _runActive = true;
                    });
                    zoomToCurrentLocation();
                    startRun();
                  },

                  shape: RoundedRectangleBorder(
                    side: const BorderSide(
                      color: Colors.black,
                      width: 2.0,
                    ),
                  ),
                  backgroundColor: Colors.white,
                  child: Text("START", style: TextStyle(color: Colors.black, fontSize: 20),
                  ),
                ),
              ), // Button Lauf starten
            if (_runActive)
              Positioned(
                right: 32,
                bottom: 16,
                width: 128,
                height: 48,
                child: FloatingActionButton(
                  onPressed: () {
                    setState(() {
                      _runActive = false;
                      _runPaused = false;
                    });
                    zoomToCurrentLocation();
                    showPopUpMenu(context);
                    pauseRun();
                  },
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(
                      color: Colors.black,
                      width: 2.0,
                    ),
                  ),
                  backgroundColor: Colors.white,
                  child: Text("STOP", style: TextStyle(color: Colors.black, fontSize: 20),
                  ),
                ),
              ), // Button Lauf beenden
            if (_runActive && !_runPaused)
              Positioned(
                left: 64,
                bottom: 16,
                width: 128,
                height: 48,
                child: FloatingActionButton(
                  onPressed: () {
                    setState(() {
                      _runPaused = true;
                    });
                    zoomToCurrentLocation();
                    pauseRun();
                  },
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(
                      color: Colors.black,
                      width: 2.0,
                    ),
                  ),
                  backgroundColor: Colors.white,
                  child: Text("PAUSE", style: TextStyle(color: Colors.black, fontSize: 20),
                  ),
                ),
              ), // Button Lauf pausieren
            if (_runActive && _runPaused)
              Positioned(
                left: 64,
                bottom: 16,
                width: 128,
                height: 48,
                child: FloatingActionButton(
                  onPressed: () {
                    setState(() {
                      _runPaused = false;
                    });
                    zoomToCurrentLocation();
                    continueRun();
                  },
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(
                      color: Colors.black,
                      width: 2.0,
                    ),
                  ),
                  backgroundColor: Colors.white,
                  child: Text("WEITER", style: TextStyle(color: Colors.black, fontSize: 20),
                  ),
                ),
              ), // Button Lauf fortsetzen
          ],
        )
    );
  }
}
