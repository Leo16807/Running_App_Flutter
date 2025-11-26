import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class CustomLatLngTween extends Tween<LatLng> {
  CustomLatLngTween({required LatLng begin, required LatLng end}) : super(begin: begin, end: end);

  @override
  LatLng lerp(double t) {
    double lat = begin!.latitude + (end!.latitude - begin!.latitude) * t;
    double lon = begin!.longitude + (end!.longitude - begin!.longitude) * t;
    return LatLng(lat, lon);
  }
}