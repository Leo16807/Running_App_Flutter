import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';
import 'dart:async';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'dart:io';
import 'permissions.dart';
import 'lat_lng_tween.dart';
import 'formatters.dart';


class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  MapScreenState createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> with WidgetsBindingObserver, TickerProviderStateMixin{
  // ---------------- Variablen ----------------
  final Logger _logger = Logger();

  LatLng _currentLocation = LatLng(0, 0);
  LatLng _startPosition = LatLng(0, 0);
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _locationReady = false;
  bool _isFirstLocationUpdate = true;
  bool _runActive = false;
  bool _runPaused = false;
  late final AnimatedMapController _animatedMapController;

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

  // ---------------- Funktionen ----------------
  @override
  void initState() {
    super.initState();
    _animatedMapController = AnimatedMapController(vsync: this);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkPermissions();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionStreamSubscription?.cancel();
    _calculationTimer?.cancel();
    _timer?.cancel();
    _animatedMapController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed){
      checkPermissions();
      _logger.d("Berechtigung wird geprüft.");
    }
  }

  Future<void> checkPermissions() async {
    bool granted = await Permissions.checkPermissions(context);
    if (granted) {
      startLocationUpdates();
    }
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
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: Platform.isAndroid
          ? AndroidSettings(
        foregroundNotificationConfig: const ForegroundNotificationConfig(
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
        _locationReady =true;
      }
    }, onError: (error) {
      _logger.e("Fehler bei Standortverfolgung: $error");
    });
  }

  void zoomToCurrentLocation() {
    _animatedMapController.animateTo(
      dest: _currentLocation,
      zoom: 16.0,
      duration: const Duration(seconds: 1),
      curve: Curves.easeInOut,
    );

  }

  void rotateNorth() {
    _animatedMapController.animateTo(
      rotation: 0,
      duration: const Duration(seconds: 1)
    );
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
    // Durchschnittswerte
    if (_totalDistance > 0) {
      _averagePace = (_elapsedTime.inSeconds) / (_totalDistance / 1000.0);
      _averageSpeed = (_totalDistance / 1000) / (_elapsedTime.inSeconds / 3600);
    } else {
      _averagePace = 0.0;
      _averageSpeed = 0.0;
    }

    // Momentanwerte (letzte 10 Sekunden)
    if (_recentDistance > 0) {
      _currentPace = 10 / (_recentDistance / 1000.0);
      _currentSpeed = (_recentDistance / 1000) / (10 / 3600);
    } else {
      _currentPace = 0.0;
      _currentSpeed = 0.0;
    }

    // Kalorien nach Aktivitätsart bestimmen
    _kcalPerKm = switch (_activityType) {
      'Gehen' => 48,
      'Laufen' => 80,
      'Fahrrad fahren' => 32,
      _ => 0,
    };

    setState(() {
      if (_averagePace > 6000) _averagePace = 0.0;
      if (_currentPace > 6000) _currentPace = 0.0;

      _kcal = _kcalPerKm * _totalDistanceInkm;
    });

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
                  Text("Zeit: ${Formatters.formatDuration(_elapsedTime)}"),
                  Text("Distanz: ${_totalDistanceInkm.toStringAsFixed(2)} km"),
                  Text("⌀Pace: ${Formatters.formatPace(_averagePace)}"),
                  Text("⌀Geschwindigkeit: ${_averageSpeed.toStringAsFixed(1)} km/h"),
                  Text("Verbrannte Kalorien: ${_kcal.toStringAsFixed(0)} kcal"),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    stopRun();
                  },
                  child: Text("Schließen"),
                ),
              ),
            ],
          ),
        );
      },
    );
  }


  // ---------------- Scaffold ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text("Running App"),
          centerTitle: true,
        ),
        body:
        FlutterMap(
          mapController: _animatedMapController.mapController,
          options: MapOptions(
            initialCenter: _currentLocation,
            initialZoom: 16,
            maxZoom: 20,
            minZoom: 1.5,
          ),
          children: [
            TileLayer(
              urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
              userAgentPackageName: "running_app/1.0 (contact: leosmolik2@gmail.com)",
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

            // Startposition und aktuelle Position auf der Karte
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
              tween: CustomLatLngTween(begin: _currentLocation, end: _currentLocation),
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

            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      "Kartendaten © OpenStreetMap-Mitwirkende",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Paramter zum Lauf
            if (_runActive)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.only(bottom: 12),
                  color: const Color(0x99000000),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Aktivität
                      Padding(
                        padding: const EdgeInsets.only(top: 12, left: 16),
                        child: Text(
                          "Aktivität: $_activityType",
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ),

                      // Laufparameter: Row mit zwei Spalten
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Linke Spalte
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 12, left: 16),
                                child: Text(
                                  "Zeit: ${Formatters.formatDuration(_elapsedTime)}",
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 12, left: 16),
                                child: Text(
                                  "⌀Pace: ${Formatters.formatPace(_averagePace)}",
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 12, left: 16),
                                child: Text(
                                  "Pace: ${Formatters.formatPace(_currentPace)}",
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                ),
                              ),
                            ],
                          ),

                          // Rechte Spalte
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: EdgeInsets.only(top: 12, right: 32),
                                child: Text(
                                  "Distanz: ${_totalDistanceInkm.toStringAsFixed(2)} km",
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 12, right: 32),
                                child: Text(
                                  "⌀Speed: ${_averageSpeed.toStringAsFixed(1)} km/h",
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 12, right: 32),
                                child: Text(
                                  "Speed: ${_currentSpeed.toStringAsFixed(1)} km/h",
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      // Verbrauchte Kalorien
                      Padding(
                        padding: const EdgeInsets.only(top: 12, left: 16),
                        child: Text(
                          "Verbrauchte Kalorien: ${_kcal.toStringAsFixed(0)} kcal",
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              )
          ],
        ),

        // Buttons zum Starte, Pausieren, Stoppen und Auswählen der AKtivität
        floatingActionButton: Stack(
          children: [
            Positioned(
              right: 16,
              bottom: 128,
              child: FloatingActionButton(
                onPressed: zoomToCurrentLocation,
                shape: CircleBorder(),
                backgroundColor: Color(0xFF5CD2ED),
                child: Icon(Icons.my_location, color: Colors.black, size: 32),
              ),
            ), // Button zentrieren

            Positioned(
              right: 20,
              bottom: 224,
              child: FloatingActionButton.small(
                onPressed: rotateNorth,
                backgroundColor: Color(0xFF5CD2ED),
                shape: CircleBorder(),
                child: Icon(Icons.navigation, color: Colors.black, ),
              )
            ),

            if (!_runActive)
              Positioned(
                left: 64,
                bottom: 32,
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
                bottom: 32,
                width: 128,
                height: 48,
                child: FloatingActionButton(
                  onPressed: _locationReady
                    ? () {
                    setState(() {
                      _runActive = true;
                    });
                    zoomToCurrentLocation();
                    startRun();
                  }
                  : null,

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
              ),
            // Button Lauf starten
            if (_runActive)
              Positioned(
                right: 32,
                bottom: 32,
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
                bottom: 32,
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
                bottom: 32,
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
