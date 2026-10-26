import SwiftUI

struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lang) private var lang
    @State private var showServer = false

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    Image("PhotoWelcome")
                        .resizable()
                        .scaledToFill()
                        .frame(height: 430)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .overlay(alignment: .bottom) {
                            LinearGradient(colors: [.clear, Brand.canvas], startPoint: .top, endPoint: .bottom)
                                .frame(height: 140)
                        }
                    Image("Wordmark")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 30)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(.white.opacity(0.92)))
                        .padding(.top, 60)
                        .padding(.leading, 20)
                }
                .overlay(alignment: .bottom) {
                    SampleNotification(
                        title: lang.t("Danger: possible scam", "Bahaya: kemungkinan penipuan"),
                        detail: lang.t("Sent to Dimas.", "Dikirim ke Dimas.")
                    )
                    .padding(.horizontal, 16)
                    .offset(y: 20)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text(lang.t("Help your family recognize phone scams.", "Bantu keluarga mengenali penipuan lewat telepon."))
                        .font(Brand.title())
                        .foregroundStyle(Brand.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(lang.t(
                        "Rambu listens to calls on speaker and warns your family when a caller shows signs of a scam.",
                        "Rambu mendengarkan telepon di loudspeaker dan memperingatkan keluarga saat penelepon menunjukkan tanda penipuan."
                    ))
                    .font(.body)
                    .foregroundStyle(Brand.ink2)
                    .fixedSize(horizontal: false, vertical: true)

                    Picker("Language", selection: Binding(get: { model.settings.language }, set: { model.setLanguage($0) })) {
                        Text("Bahasa Indonesia").tag(Lang.id)
                        Text("English").tag(Lang.en)
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 8)

                    Button {
                        model.settings.role = .parent
                    } label: {
                        Label(lang.t("I am the protected parent", "Saya orang tua yang dilindungi"), systemImage: "shield.lefthalf.filled")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 4)

                    Button {
                        model.settings.role = .caregiver
                    } label: {
                        Label(lang.t("I am a caregiver", "Saya pengawas"), systemImage: "person.2.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button(lang.t("Server", "Server")) { showServer = true }
                        .font(.footnote)
                        .foregroundStyle(Brand.ink3)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 44)
                .padding(.bottom, 24)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Brand.canvas.ignoresSafeArea())
        .sheet(isPresented: $showServer) { ServerSheet() }
    }
}

/// A Rambu notification drawn in the app (used on Welcome and in the practice run).
struct SampleNotification: View {
    var title: String
    var detail: String
    var mascot: String = "mascot-stop-danger"

    var body: some View {
        HStack(spacing: 12) {
            Image("RambuIcon")
                .resizable()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("RAMBU").font(.caption.weight(.semibold)).foregroundStyle(Brand.ink3)
                    Spacer()
                    Text("now").font(.caption).foregroundStyle(Brand.ink3)
                }
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
                Text(detail).font(.subheadline).foregroundStyle(Brand.ink2)
            }
            Image(mascot)
                .resizable()
                .scaledToFit()
                .frame(width: 46, height: 52)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.redSoft))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.ultraThinMaterial))
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.white.opacity(0.7)))
        .shadow(color: Brand.ink.opacity(0.12), radius: 16, y: 6)
    }
}
