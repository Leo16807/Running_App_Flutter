class Formatters {
  static String formatDuration(Duration duration) {
    int hours = duration.inHours;
    int minutes = duration.inMinutes.remainder(60);
    int seconds = duration.inSeconds.remainder(60);

    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  static String formatPace(double paceInSecondsPerKm) {
    if (paceInSecondsPerKm.isNaN ||
        paceInSecondsPerKm.isInfinite ||
        paceInSecondsPerKm <= 0) {
      return "00:00 min/km";
    }
    int minutes = (paceInSecondsPerKm ~/ 60);
    int seconds = (paceInSecondsPerKm % 60).toInt();
    return "$minutes:${seconds.toString().padLeft(2, '0')} min/km";
  }

}