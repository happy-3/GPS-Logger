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

### テスト用の手入力

Flight Assist 画面では、計測値を検証するためにグランドトラック (GT) と
グランドスピード (GS) を手動で入力してサンプルとして追加することができ
ます。これにより、実際の GPS 信号がなくてもデータ収集ロジックを確認
できます。

## Map Overlays

The app displays a basemap from an MBTiles file and optional airspace overlays from GeoJSON or vector MBTiles files. Data placed in the `Airspace` directory is loaded when the map view is created. Each file is treated as a category identified by its filename without the extension. GeoJSON files are parsed on a background thread and converted to `MKPolyline`, `MKPolygon` or `MKCircle` objects depending on the geometry type. Vector MBTiles are read tile by tile so only features within the current map view are loaded.
`MBTilesVectorSource` は読み込んだタイルを内部でキャッシュしており、`cacheLimit` プロパティで保持数を指定できます。上限を超えた場合は古いタイルから削除されます。

When you open the map screen, tap the stack icon in the toolbar to show the layer settings. A list of categories appears and you can toggle each overlay on or off. The map refreshes immediately to reflect your choices.

The bundled `jp_asp.geojson` file contains many different airspace types. When loaded, these features are automatically classified into sub‑categories such as `TCA`, `CTR` or `JSDF`. Each sub‑category appears as its own item in the layer settings under a major group like "Terminal Control Airspace". Stroke and fill colors can be adjusted per sub‑category using the color pickers in the settings screen.

`LineString` と `Polygon` に加え `Point` 形式のフィーチャもサポートしています。`Point` は半径 300 m の円として表示されます。Multi‑geometry types are ignored. To add new data, bundle additional GeoJSON or vector MBTiles files in the `Airspace` folder. GeoJSON can be converted using `tools/geojson_to_mbtiles.sh`.

**Note:** サンプルの空域データはリポジトリに含まれていません。`Airspace` フォルダへ GeoJSON または MBTiles ファイルを配置してからビルドしてください。ファイルが存在しない場合、マップ上にはベースマップのみが表示されます。

## ナビゲーション機能

マップ画面でウェイポイントを設定すると、目標地点への方位・距離・ETE/ETA を計算して表示する簡易ナビゲーションを利用できます。この処理は `MainMapView` 内の `updateNav()` で行われ、結果は中央の `TargetBannerView` に反映されます。

### 操作手順
1. 地図上をタップするとその地点がウェイポイントとして登録されます。
2. 中央のバナーに方位、距離、ETE、ETA が表示されます。
3. 長押しするとウェイポイントとバナーが消去されます。
4. ピンチ操作でレンジリングの半径を調整できます。

### Day/Night 切替
設定画面の「Display Options」にある `Night テーマ` スイッチでモードを切り替えられます。`useNightTheme` が有効なときは `RangeRingNight` や `TrackNight` の色が使用され、無効時は Day 用カラーが使われます。
