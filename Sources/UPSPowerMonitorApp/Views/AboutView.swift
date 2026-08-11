import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)

            BatteryLogoView(size: 104)

            VStack(spacing: 10) {
                Text("Version 1.0.21")
                    .font(.system(size: 18))
                    .foregroundStyle(.primary)

                Text("UPS 在线监控，一款优雅关机工具。")

                Text("Copyright 2026 Han")
                Text("Licensed under the Apache License, Version 2.0")
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
}
