import SwiftUI
import CoreLocation

/// HUD 表示を行う View
struct HUDView: View {
    @ObservedObject var viewModel: HUDViewModel
    var body: some View {
        VStack(spacing: 4) {
            ForEach(viewModel.hudRows, id: \.self) { row in
                Text(row)
                    .font(.caption2.monospaced())
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.5))
        .cornerRadius(8)
    }
}

/// Map タップ時に表示する一覧
struct StackChipView: View {
    let list: [AirspaceSlim]
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(list) { asp in
                Text(String(format: "%@-%@ %-4@ %@", asp.upper, asp.lower, asp.sub, asp.icon))
                    .font(.caption2.monospaced())
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.7))
        .cornerRadius(8)
    }
}
