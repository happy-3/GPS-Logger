import SwiftUI

/// 空域レイヤの表示設定を行う画面
struct MapLayerSettingsView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var airspaceManager: AirspaceManager

    var body: some View {
        Form {
            if !airspaceManager.categories.isEmpty {
                Section(header: Text("空域レイヤ")) {
                    ForEach(airspaceManager.categories, id: \.self) { category in
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
                    }
                }
            }
        }
        .navigationTitle("レイヤ設定")
    }
}

# Preview
struct MapLayerSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        MapLayerSettingsView()
            .environmentObject(Settings())
            .environmentObject(AirspaceManager(settings: Settings()))
    }
}
