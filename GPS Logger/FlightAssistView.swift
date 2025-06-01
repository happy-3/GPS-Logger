import SwiftUI

/// Flight Assist の表示とレグ管理を行うビュー。
struct FlightAssistView: View {
    // 現状はダミーの数値を表示するのみ
    @State private var tas: Double = 250.0
    @State private var cas: Double = 245.0
    @State private var hp: Double = 5000.0
    @State private var deltaCas: Double = 0.0

    var body: some View {
        VStack(spacing: 30) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("TAS")
                    Spacer()
                    Text(String(format: "%.1f kt", tas))
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                }
                HStack {
                    Text("CAS")
                    Spacer()
                    Text(String(format: "%.1f kt", cas))
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                }
                HStack {
                    Text("Hₚ")
                    Spacer()
                    Text(String(format: "%.0f ft", hp))
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                }
                HStack {
                    Text("ΔCAS")
                    Spacer()
                    Text(String(format: "%.1f kt", deltaCas))
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)

            HStack(spacing: 40) {
                Button("Start") {
                    // TODO: ログ区切り開始処理を実装
                }
                .frame(width: 80, height: 50)
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)

                Button("Turn") {
                    // TODO: レグ変更処理を実装
                }
                .frame(width: 80, height: 50)
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(10)

                Button("Stop") {
                    // TODO: ログ区切り終了処理を実装
                }
                .frame(width: 80, height: 50)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Flight Assist")
    }
}

struct FlightAssistView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            FlightAssistView()
        }
    }
}
