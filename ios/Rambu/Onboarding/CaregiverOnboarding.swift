import SwiftUI

struct CaregiverOnboarding: View {
    @Environment(AppModel.self) private var model
    @State private var step: Step = .code
    @State private var code = ""

    enum Step { case code, profile, waiting }

    var body: some View {
        Group {
            switch step {
            case .code:
                EnterCodeStep(code: $code, onNext: { step = .profile }, onBack: { model.settings.role = nil })
            case .profile:
                CaregiverProfileStep(code: code, onJoined: { step = .waiting }, onBack: { step = .code })
            case .waiting:
                WaitingForAllowStep(onAllowed: { model.finishOnboarding() })
            }
        }
        .animation(.easeInOut(duration: 0.2), value: step)
        .onAppear { if model.isLinked { step = .waiting } }
    }
}

struct EnterCodeStep: View {
    @Binding var code: String
    var onNext: () -> Void
    var onBack: () -> Void
    @Environment(\.lang) private var lang

    var body: some View {
        StepScaffold(
            step: 1, total: 3,
            title: lang.t("Enter code", "Masukkan kode"),
            subtitle: lang.t("The 6-digit code from your parent's Rambu app.", "Kode 6 angka dari aplikasi Rambu orang tua Anda."),
            onBack: onBack
        ) {
            CodeBoxes(code: code, active: true)
        } footer: {
            VStack(spacing: 12) {
                Button(lang.t("Continue", "Lanjut"), action: onNext)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(code.count != 6)
                NumberPad(code: $code)
            }
        }
    }
}

struct NumberPad: View {
    @Binding var code: String

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(keys, id: \.self) { key in
                if key.isEmpty {
                    Color.clear.frame(height: 48)
                } else {
                    Button {
                        if key == "⌫" {
                            if !code.isEmpty { code.removeLast() }
                        } else if code.count < 6 {
                            code.append(key)
                        }
                    } label: {
                        Group {
                            if key == "⌫" { Image(systemName: "delete.left") } else { Text(key) }
                        }
                        .font(.title2.weight(.medium))
                        .foregroundStyle(Brand.ink)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(key == "⌫" ? .clear : .white))
                    }
                    .accessibilityLabel(key == "⌫" ? "Delete" : key)
                }
            }
        }
    }
}

struct CaregiverProfileStep: View {
    var code: String
    var onJoined: () -> Void
    var onBack: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.lang) private var lang
    @State private var name = ""
    @State private var relationship: Relationship = .child
    @State private var working = false
    @State private var error: String?

    var body: some View {
        StepScaffold(step: 2, total: 3, title: lang.t("Who are you?", "Siapa Anda?"), onBack: onBack) {
            VStack(alignment: .leading, spacing: 10) {
                Text(lang.t("Your name", "Nama Anda")).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink2)
                TextField(lang.t("Your name", "Nama Anda"), text: $name)
                    .font(.title3)
                    .textContentType(.givenName)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Brand.hairline))
                Text(lang.t("Relationship", "Hubungan")).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink2).padding(.top, 12)
                HStack(spacing: 8) {
                    ForEach(Relationship.allCases, id: \.self) { option in
                        Button(option.label(lang)) { relationship = option }
                            .font(.headline)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 48)
                            .foregroundStyle(relationship == option ? .white : Brand.ink)
                            .background(Capsule().fill(relationship == option ? Brand.teal : .white))
                    }
                }
                if let error { ErrorLine(text: error).padding(.top, 12) }
            }
        } footer: {
            Button {
                Task { await join() }
            } label: {
                if working { ProgressView().tint(.white) } else { Text(lang.t("Continue", "Lanjut")) }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || working)
        }
        .onAppear {
            name = model.settings.name
            relationship = model.settings.relationship
        }
    }

    private func join() async {
        working = true
        defer { working = false }
        model.settings.name = name.trimmingCharacters(in: .whitespaces)
        model.settings.relationship = relationship
        do {
            try await model.join(code: code)
            onJoined()
        } catch let failure as APIError {
            switch failure.status {
            case 404: error = lang.t("That code doesn't exist. Check it with your parent.", "Kode tidak ditemukan. Cek lagi dengan orang tua Anda.")
            case 410: error = lang.t("That code has expired. Ask for a new one.", "Kode sudah kedaluwarsa. Minta kode baru.")
            default: error = lang.t("Can't reach the Rambu server. Check the Server address.", "Server Rambu tidak terjangkau. Periksa alamat Server.")
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct WaitingForAllowStep: View {
    var onAllowed: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.lang) private var lang

    var body: some View {
        StepScaffold(
            step: 3, total: 3,
            title: lang.t("Waiting for approval", "Menunggu persetujuan"),
            subtitle: lang.t("Ask your parent to tap Allow on their phone.", "Minta orang tua Anda menekan Izinkan di HP-nya."),
            onBack: nil
        ) {
            VStack(spacing: 20) {
                Image("mascot-wave").resizable().scaledToFit().frame(height: 180)
                ProgressView()
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
        } footer: {
            EmptyView()
        }
        .task {
            while !Task.isCancelled {
                await model.refreshFamily()
                if model.isApproved { onAllowed(); return }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
