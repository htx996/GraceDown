import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)

            BatteryLogoView(size: 104)

            VStack(spacing: 8) {
                Text("GraceDown")
                    .font(.system(size: 26, weight: .bold))

                Text(versionText)
                    .font(.system(size: 18))
                    .foregroundStyle(.primary)
            }

            VStack(spacing: 4) {
                Text("macOS 菜单栏 UPS 电源监控工具")
                Text("Copyright © 2026 Han. Open source under the MIT License.")
            }
            .font(.system(size: 15))
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 30)
        .frame(width: 520, height: 360)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "Version \(version) (\(build))"
    }
}
