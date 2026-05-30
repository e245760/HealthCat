import SwiftUI
import Combine

struct TimeBasedGradient: View {
    // 1分ごとに更新
    @State private var currentHour: Int = Calendar.current.component(.hour, from: Date())
    @State private var currentMinute: Int = Calendar.current.component(.minute, from: Date())

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        LinearGradient(
            colors: gradientColors,
            startPoint: .top,
            endPoint: .bottom
        )
        .animation(.easeInOut(duration: 2.0), value: currentHour)
        .onReceive(timer) { _ in
            currentHour = Calendar.current.component(.hour, from: Date())
            currentMinute = Calendar.current.component(.minute, from: Date())
        }
    }

    // MARK: - 時間帯ごとの色

    private var gradientColors: [Color] {
        switch currentHour {
        case 5..<7:
            // 夜明け: 濃い青 → オレンジ
            return [
                Color(red: 0.1, green: 0.1, blue: 0.35),
                Color(red: 0.9, green: 0.5, blue: 0.2),
            ]
        case 7..<10:
            // 朝: 明るいオレンジ → 薄い黄色
            return [
                Color(red: 0.99, green: 0.75, blue: 0.4),
                Color(red: 0.99, green: 0.95, blue: 0.75),
            ]
        case 10..<16:
            // 昼: 水色 → 白っぽい青
            return [
                Color(red: 0.45, green: 0.75, blue: 0.99),
                Color(red: 0.8, green: 0.92, blue: 0.99),
            ]
        case 16..<18:
            // 夕方: オレンジ → ピンク
            return [
                Color(red: 0.99, green: 0.55, blue: 0.2),
                Color(red: 0.99, green: 0.75, blue: 0.65),
            ]
        case 18..<20:
            // 夕暮れ: 濃いオレンジ → 紫
            return [
                Color(red: 0.7, green: 0.2, blue: 0.3),
                Color(red: 0.3, green: 0.1, blue: 0.45),
            ]
        case 20..<23:
            // 夜: 濃い紺 → 深い青
            return [
                Color(red: 0.05, green: 0.05, blue: 0.2),
                Color(red: 0.1, green: 0.1, blue: 0.35),
            ]
        default:
            // 深夜: 黒に近い紺
            return [
                Color(red: 0.02, green: 0.02, blue: 0.12),
                Color(red: 0.05, green: 0.05, blue: 0.2),
            ]
        }
    }
}
