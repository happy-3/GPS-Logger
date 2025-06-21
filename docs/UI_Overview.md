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

## レンジリングと航跡線

レンジリングは中心から 4 本描画され、最外周リングまで現在のグランドトラック方向に半透明のラインが伸びます。ライン上には 1 分後を示す矢印と、2〜5 分後までの丸印が描かれます。距離ラベルはラインとリングの交点近くへ配置され、航跡線と重ならないよう少し横へずらしています。GPS 受信が不良でトラックが不明な場合は航跡線を表示せず、画面を赤く点滅させて警告します。
