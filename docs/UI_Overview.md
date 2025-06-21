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

レンジリングは中心から 4 本描画され、最外周リングまで現在のグランドトラック方向に航跡線が伸びます。グランドスピードに基づき 1 分毎の目盛りも追加され、航跡線上に短いティックとして表示されます。各リングの東側には距離ラベルが配置され、"1 NM" などの形式で現在位置からの距離を示します。ラベルは半透明の背景を持ち、Day/Night テーマに合わせて文字色が変わります。
