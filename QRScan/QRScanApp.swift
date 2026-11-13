import SwiftUI

@main
struct QRScanApp: App {
    var body: some Scene {
        WindowGroup {
            ScannerView()
        }
    }
}

extension Color {
    static let scanMint = Color(red: 0.47, green: 0.94, blue: 0.73)
    static let scanInk = Color(red: 0.05, green: 0.11, blue: 0.09)
}
