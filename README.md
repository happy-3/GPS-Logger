# GPS Logger

This project records flight log data using Core Location and sensor fusion.
Each recording session saves logs in a uniquely timestamped folder inside the
app's document directory.

## Measurement Logs

When you perform a distance measurement, the logs used to generate the altitude
chart are exported automatically. A CSV file named
`MeasurementLog_YYYYMMDD_HHmmss.csv` is written inside the same session folder
as the regular flight log CSVs. Each row contains the timestamp, GPS altitude,
Kalman‑fused altitude and corresponding change rates for that measurement.

These measurement logs make it easy to review altitude changes for a specific
distance measurement alongside the overall flight log.
