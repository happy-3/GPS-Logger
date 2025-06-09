import SwiftUI
import MapKit

/// 空域レイヤの表示設定を行う画面
struct MapLayerSettingsView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var airspaceManager: AirspaceManager

    var body: some View {
        Form {
            if !airspaceManager.categories.isEmpty {
                Section(header: Text("空域レイヤ")) {
                    ForEach(airspaceManager.categories, id: \.self) { category in
                        CategorySettingsView(category: category)
                    }
                }
            }
        }
        .navigationTitle("レイヤ設定")
    }
}

private struct CategorySettingsView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var airspaceManager: AirspaceManager
    let category: String

    var body: some View {
        VStack(alignment: .leading) {
            Toggle(category, isOn: Binding(
                get: { settings.enabledAirspaceCategories.contains(category) },
                set: { newValue in
                    if newValue {
                        if !settings.enabledAirspaceCategories.contains(category) {
                            settings.enabledAirspaceCategories.append(category)
                        }
                    } else {
                        settings.enabledAirspaceCategories.removeAll { $0 == category }
                    }
                }
            ))

            if settings.enabledAirspaceCategories.contains(category) {
                let features = airspaceManager.features(in: category)
                ForEach(features.indices, id: \.self) { idx in
                    let overlay = features[idx]
                    let fid = (overlay as? FeaturePolyline)?.featureID ??
                              (overlay as? FeaturePolygon)?.featureID ??
                              (overlay as? FeatureCircle)?.featureID ??
                              "\(idx)"
                    let title = (overlay as? MKShape)?.title ?? "Feature \(idx)"
                    Toggle("  " + title, isOn: Binding(
                        get: { !(settings.hiddenFeatureIDs[category] ?? []).contains(fid) },
                        set: { val in
                            var list = settings.hiddenFeatureIDs[category] ?? []
                            if val {
                                list.removeAll { $0 == fid }
                            } else {
                                if !list.contains(fid) { list.append(fid) }
                            }
                            settings.hiddenFeatureIDs[category] = list
                        }
                    ))
                }

                ColorPicker("線色", selection: Binding(
                    get: { Color(hex: settings.airspaceStrokeColors[category] ?? "FF0000FF") ?? .red },
                    set: { color in settings.airspaceStrokeColors[category] = color.hexString }
                ))
                ColorPicker("塗り色", selection: Binding(
                    get: { Color(hex: settings.airspaceFillColors[category] ?? "FF000055") ?? .blue.opacity(0.2) },
                    set: { color in settings.airspaceFillColors[category] = color.hexString }
                ))
            }
        }
    }
}

// MARK: - Preview
struct MapLayerSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        MapLayerSettingsView()
            .environmentObject(Settings())
            .environmentObject(AirspaceManager(settings: Settings()))
    }
}
