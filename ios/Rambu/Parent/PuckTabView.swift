import SwiftUI

/// Parent's Puck tab: status only. Pairing from the app is deferred to the next hardware phase.
struct PuckTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lang) private var lang

    private enum PuckState { case online, offline, notSetUp }

    var body: some View {
        let puck = model.family?.puck
        let state: PuckState = puck == nil ? .notSetUp : (puck!.online ? .online : .offline)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    ProfileButton()
                }
                Text("Puck").font(Brand.title()).foregroundStyle(Brand.ink)

                Image("PhotoPuckProduct")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                Card(padding: 0) {
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Circle().fill(color(state)).frame(width: 12, height: 12)
                            Text(title(state)).font(.headline).foregroundStyle(Brand.ink)
                            Spacer()
                        }
                        .padding(16)
                        if let puck {
                            Divider().padding(.leading, 16)
                            row(lang.t("Firmware", "Firmware"), puck.firmware ?? "–")
                            Divider().padding(.leading, 16)
                            row(lang.t("Last seen", "Terakhir terlihat"),
                                puck.lastSeenAt.map { CallFormat.when($0, lang: lang) } ?? lang.t("Never", "Belum pernah"))
                        }
                    }
                }

                if state == .offline {
                    Text(lang.t("Calls aren't checked while the puck is offline. Check its cable and Wi-Fi.",
                                "Panggilan tidak diperiksa saat puck tidak terhubung. Cek kabel dan Wi-Fi-nya."))
                        .font(.subheadline).foregroundStyle(Brand.ink2)
                }

                Label(lang.t("Pairing from the app comes with the next hardware phase.",
                             "Pemasangan lewat aplikasi hadir di fase perangkat berikutnya."),
                      systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Brand.ink3)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .background(Brand.canvas.ignoresSafeArea())
        .refreshable { await model.refreshFamily() }
        .task { await model.refreshFamily() }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Brand.ink2)
            Spacer()
            Text(value).foregroundStyle(Brand.ink)
        }
        .font(.subheadline)
        .padding(16)
    }

    private func title(_ state: PuckState) -> String {
        switch state {
        case .online: lang.t("Online", "Terhubung")
        case .offline: lang.t("Offline", "Tidak terhubung")
        case .notSetUp: lang.t("Not set up yet", "Belum diatur")
        }
    }

    private func color(_ state: PuckState) -> Color {
        switch state {
        case .online: Brand.green
        case .offline: Brand.red
        case .notSetUp: Brand.ink3
        }
    }
}
