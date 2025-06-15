import SwiftUI
import MapKit

/// 空域レイヤの表示設定を行う画面
struct MapLayerSettingsView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var airspaceManager: AirspaceManager

    var body: some View {
        Form {
            Picker("Orientation", selection: $settings.orientationMode) {
                ForEach(Settings.MapOrientationMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            if !airspaceManager.groups.isEmpty {
                ForEach(airspaceManager.groups, id: \.self) { group in
                    Section {
                        ForEach(airspaceManager.categories(inGroup: group), id: \.self) { category in
                            CategorySettingsView(category: category)
                        }
                    } header: {
                        GroupHeaderView(group: group)
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

                    let group = airspaceManager.group(for: category)
                    let cats = airspaceManager.categories(inGroup: group)
                    let anyEnabled = cats.contains { settings.enabledAirspaceCategories.contains($0) }
                    if anyEnabled {
                        if !settings.enabledAirspaceGroups.contains(group) {
                            settings.enabledAirspaceGroups.append(group)
                        }
                    } else {
                        settings.enabledAirspaceGroups.removeAll { $0 == group }
                    }
                }
            ))

            if settings.enabledAirspaceCategories.contains(category) {
                ForEach(airspaceManager.featureGroups(in: category), id: \.self) { g in
                    let overlays = airspaceManager.features(in: category, group: g)
                    Toggle("  " + g, isOn: Binding(
                        get: {
                            let hidden = Set(settings.hiddenFeatureIDs[category] ?? [])
                            return !overlays.allSatisfy { ov in
                                let fid = (ov as? FeaturePolyline)?.featureID ??
                                          (ov as? FeaturePolygon)?.featureID ??
                                          (ov as? FeatureCircle)?.featureID ?? ""
                                return hidden.contains(fid)
                            }
                        },
                        set: { val in
                            var list = settings.hiddenFeatureIDs[category] ?? []
                            for ov in overlays {
                                let fid = (ov as? FeaturePolyline)?.featureID ??
                                          (ov as? FeaturePolygon)?.featureID ??
                                          (ov as? FeatureCircle)?.featureID ?? ""
                                if val {
                                    list.removeAll { $0 == fid }
                                } else if !list.contains(fid) {
                                    list.append(fid)
                                }
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

private struct GroupHeaderView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var airspaceManager: AirspaceManager
    let group: String

    var body: some View {
        Toggle(group, isOn: Binding(
            get: { settings.enabledAirspaceGroups.contains(group) },
            set: { newValue in
                let cats = airspaceManager.categories(inGroup: group)
                if newValue {
                    if !settings.enabledAirspaceGroups.contains(group) {
                        settings.enabledAirspaceGroups.append(group)
                    }
                    for cat in cats {
                        if !settings.enabledAirspaceCategories.contains(cat) {
                            settings.enabledAirspaceCategories.append(cat)
                        }
                    }
                } else {
                    settings.enabledAirspaceGroups.removeAll { $0 == group }
                    settings.enabledAirspaceCategories.removeAll { cats.contains($0) }
                }
            }
        ))
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
