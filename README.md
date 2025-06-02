# GPS Logger

This project records flight log data using Core Location and sensor fusion.
Each recording session saves logs in a uniquely timestamped folder inside the
app's document directory.

The Kalman filter used for altitude fusion can be enabled or disabled from the
Settings screen. When disabled, the app shows raw GPS altitude and vertical rate
without Kalman processing.

## Measurement Logs

When you perform a distance measurement, the logs used to generate the altitude
chart are exported automatically. A CSV file named
`MeasurementLog_YYYYMMDD_HHmmss.csv` is written inside the same session folder
as the regular flight log CSVs. Each row contains the timestamp, GPS altitude,
Kalman‑fused altitude and corresponding change rates for that measurement.

These measurement logs make it easy to review altitude changes for a specific
distance measurement alongside the overall flight log.

## Wind Calculation Notes

Aircraft heading inputs on the Flight Assist screen should be entered in
**magnetic** degrees. The app automatically converts them to true heading using
the device's current magnetic declination when performing wind calculations.
Wind direction values shown in the UI are also displayed in magnetic degrees so
that pilots can reference them directly. The underlying log records keep the
true wind direction for later analysis.
