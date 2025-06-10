# UIレイヤ構成とカラーパレット

## UIレイヤ構成
```
MainMapView
├─ MapViewRepresentable (UIKit)
│  └─ MKMapView + Coordinator
├─ TargetBannerView
├─ StatusRibbonView
└─ HUDView / StackChipView
```
各レイヤは `MainMapView` の上に ZStack で重ねて表示されます。`MapViewRepresentable` が地図描画とジェスチャ処理を担当し、他のビューはナビゲーション情報や HUD をオーバーレイとして配置します。

## カラーパレット
`Assets.xcassets` には Day/Night 用の色が定義されています。

| Asset 名          | 用途             |
|-------------------|------------------|
| `RangeRingDay`    | 日中モードのレンジリング色 |
| `RangeRingNight`  | Night モードのレンジリング色 |
| `TrackDay`        | 日中モードの航跡線色 |
| `TrackNight`      | Night モードの航跡線色 |

`Settings.useNightTheme` が `true` の場合、Night 用カラーが選択されます。
