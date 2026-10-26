import AVFoundation
import SwiftUI

struct ParentOnboarding: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lang) private var lang
    @State private var step: Step = .tutorial

    enum Step: Int, CaseIterable { case tutorial, name, puck, ready, invite, practice }

    var body: some View {
        Group {
            switch step {
            case .tutorial: TutorialView(onDone: { step = .name }, onBack: { model.settings.role = nil })
            case .name: ParentNameStep(onNext: { step = .puck }, onBack: { step = .tutorial })
            case .puck: AttachPuckStep(onNext: { step = .ready }, onBack: { step = .name })
            case .ready: BeforeYouBeginStep(onNext: { step = .invite }, onBack: { step = .puck })
            case .invite: InviteStep(onNext: { step = .practice }, onBack: nil)
            case .practice: ParentPracticeView(onDone: { model.finishOnboarding() })
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: step)
    }
}

// MARK: - Tutorial

struct TutorialView: View {
    var onDone: () -> Void
    var onBack: () -> Void
    @Environment(\.lang) private var lang
    @State private var page = 0
    @State private var speaker = AVSpeechSynthesizer()

    private var cards: [(image: String, title: String, detail: String)] {
        [
            ("PhotoPuckOnPhone",
             lang.t("Attach the puck to the phone", "Tempel puck di HP"),
             lang.t("On the back of the phone, like a grip.", "Di punggung HP, seperti pegangan.")),
            ("PhotoSpeakerCall",
             lang.t("Answer calls on speaker", "Angkat telepon dengan loudspeaker"),
             lang.t("The puck can only hear what comes out of the speaker.", "Puck hanya bisa mendengar suara dari loudspeaker.")),
            ("PhotoGuardian",
             lang.t("Your family checks with you", "Keluarga ikut memeriksa"),
             lang.t("If a caller sounds like a scam, your child sees the exact words and tells you what to do.",
                    "Kalau penelepon terdengar seperti penipu, anak Anda melihat kalimatnya dan memberi tahu apa yang harus dilakukan.")),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(lang.t("Back", "Kembali"), action: onBack).foregroundStyle(Brand.teal)
                Spacer()
                Button {
                    speak()
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(Brand.teal)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(.white))
                }
                .accessibilityLabel(lang.t("Read aloud", "Bacakan"))
            }
            .padding(.horizontal, 20)

            TabView(selection: $page) {
                ForEach(cards.indices, id: \.self) { index in
                    VStack(spacing: 20) {
                        Color.clear
                            .frame(height: 340)
                            .overlay(Image(cards[index].image).resizable().scaledToFill())
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                            .padding(.horizontal, 20)
                        Text(cards[index].title)
                            .font(Brand.title(.title))
                            .foregroundStyle(Brand.ink)
                            .multilineTextAlignment(.center)
                        Text(cards[index].detail)
                            .font(.body)
                            .foregroundStyle(Brand.ink2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                        Spacer(minLength: 0)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 6) {
                ForEach(cards.indices, id: \.self) { index in
                    Capsule().fill(index == page ? Brand.teal : Brand.hairline).frame(width: index == page ? 22 : 8, height: 8)
                }
            }
            .padding(.bottom, 16)

            Button(lang.t("Continue", "Lanjut")) {
                if page < cards.count - 1 { withAnimation { page += 1 } } else { onDone() }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(Brand.canvas.ignoresSafeArea())
        .onDisappear { speaker.stopSpeaking(at: .immediate) }
    }

    private func speak() {
        speaker.stopSpeaking(at: .immediate)
        let card = cards[page]
        let utterance = AVSpeechUtterance(string: "\(card.title). \(card.detail)")
        utterance.voice = AVSpeechSynthesisVoice(language: lang == .en ? "en-US" : "id-ID")
        speaker.speak(utterance)
    }
}

// MARK: - Steps

struct ParentNameStep: View {
    var onNext: () -> Void
    var onBack: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.lang) private var lang
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        StepScaffold(step: 1, total: 5, title: lang.t("What is your name?", "Siapa nama Anda?"), onBack: onBack) {
            TextField(lang.t("Your name", "Nama Anda"), text: $name)
                .font(.title3)
                .textContentType(.name)
                .focused($focused)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Brand.hairline))
            Text(lang.t("Your family sees this name in warnings.", "Keluarga melihat nama ini di peringatan."))
                .font(.footnote)
                .foregroundStyle(Brand.ink3)
                .padding(.top, 8)
        } footer: {
            Button(lang.t("Continue", "Lanjut")) {
                model.setName(name.trimmingCharacters(in: .whitespaces))
                onNext()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onAppear {
            name = model.settings.name
            focused = name.isEmpty
        }
    }
}

struct AttachPuckStep: View {
    var onNext: () -> Void
    var onBack: () -> Void
    @Environment(\.lang) private var lang

    var body: some View {
        StepScaffold(
            step: 2, total: 5,
            title: lang.t("Attach the puck", "Pasang puck"),
            subtitle: lang.t("Stick it to the back of the phone and plug in its cable.", "Tempel di punggung HP lalu colok kabelnya."),
            onBack: onBack
        ) {
            Image("PhotoPuckProduct")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        } footer: {
            VStack(spacing: 8) {
                PuckSetupButton(onPaired: onNext)
                Button(lang.t("Set up later", "Atur nanti"), action: onNext)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.teal)
                    .frame(minHeight: 44)
            }
        }
    }
}

struct BeforeYouBeginStep: View {
    var onNext: () -> Void
    var onBack: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.lang) private var lang
    @State private var working = false
    @State private var error: String?

    var body: some View {
        StepScaffold(step: 3, total: 5, title: lang.t("Before you begin", "Sebelum mulai"), onBack: onBack) {
            VStack(spacing: 10) {
                IconRow(symbol: "speaker.wave.3.fill",
                        title: lang.t("Use speakerphone during calls", "Pakai loudspeaker saat menelepon"),
                        detail: lang.t("The call must be clearly audible to be checked.", "Suara telepon harus jelas terdengar agar bisa diperiksa."))
                IconRow(symbol: "quote.bubble.fill",
                        title: lang.t("Family sees relevant excerpts", "Keluarga melihat kutipan penting"),
                        detail: lang.t("Only the caller's suspicious sentences, never the whole call.", "Hanya kalimat penelepon yang mencurigakan, bukan seluruh percakapan."))
                IconRow(symbol: "bell.badge.fill",
                        title: lang.t("Alerts come as notifications", "Peringatan muncul sebagai notifikasi"),
                        detail: lang.t("At the top of the screen, even during a call.", "Di atas layar, bahkan saat menelepon."))
                IconRow(symbol: "hand.raised.fill",
                        title: lang.t("You stay in control", "Anda tetap memegang kendali"),
                        detail: lang.t("Rambu never hangs up your call.", "Rambu tidak pernah menutup telepon Anda."))
            }
            if let error { ErrorLine(text: error).padding(.top, 12) }
        } footer: {
            Button {
                Task { await begin() }
            } label: {
                if working { ProgressView().tint(.white) } else { Label(lang.t("Continue", "Lanjut"), systemImage: "checkmark") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(working)
        }
    }

    private func begin() async {
        if model.isLinked { onNext(); return }
        working = true
        defer { working = false }
        do {
            try await model.createFamily()
            error = nil
            onNext()
        } catch {
            self.error = lang.t("Can't reach the Rambu server. Check the Server address.", "Server Rambu tidak terjangkau. Periksa alamat Server.")
        }
    }
}

struct InviteStep: View {
    var onNext: () -> Void
    var onBack: (() -> Void)?
    @Environment(\.lang) private var lang
    @Environment(AppModel.self) private var model

    var body: some View {
        StepScaffold(
            step: 4, total: 5,
            title: lang.t("Invite a caregiver", "Undang pengawas"),
            subtitle: lang.t("Give this code to your child. They enter it in their Rambu app.", "Berikan kode ini ke anak Anda. Mereka memasukkannya di aplikasi Rambu."),
            onBack: onBack
        ) {
            InvitePanel()
        } footer: {
            VStack(spacing: 8) {
                Button(lang.t("Continue", "Lanjut"), action: onNext)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.family?.caregivers.isEmpty ?? true)
                Button(lang.t("Invite later", "Undang nanti"), action: onNext)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.teal)
                    .frame(minHeight: 44)
            }
        }
    }
}

/// Invite code with its countdown plus incoming requests; used in onboarding and from Home.
struct InvitePanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lang) private var lang

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 14) {
                let invite = model.family?.invite
                let valid = invite.map { $0.expiresAt > context.date } ?? false
                CodeBoxes(code: valid ? invite!.code : "")
                    .opacity(valid ? 1 : 0.5)
                if let invite, valid {
                    let minutes = Int(ceil(invite.expiresAt.timeIntervalSince(context.date) / 60))
                    Label(lang.t("Valid for \(minutes) more min", "Berlaku \(minutes) menit lagi"), systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(Brand.ink2)
                    ShareLink(item: lang.t("My Rambu invite code: \(invite.code)", "Kode undangan Rambu saya: \(invite.code)")) {
                        Label(lang.t("Share code", "Bagikan kode"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PillButtonStyle())
                } else {
                    ErrorLine(text: lang.t("Create a new code to share an invitation.", "Buat kode baru untuk membagikan undangan."))
                    Button(lang.t("New code", "Kode baru")) { Task { await model.renewInvite() } }
                        .buttonStyle(PillButtonStyle())
                }

                let pending = model.family?.pending ?? []
                let joined = model.family?.caregivers ?? []
                if !pending.isEmpty || !joined.isEmpty {
                    Text(lang.t("Requests", "Permintaan"))
                        .font(.headline)
                        .foregroundStyle(Brand.ink)
                        .padding(.top, 8)
                    Card(padding: 4) {
                        VStack(spacing: 0) {
                            ForEach(pending + joined) { member in
                                HStack(spacing: 12) {
                                    Avatar(name: member.name, color: personColor(member.id))
                                    VStack(alignment: .leading) {
                                        Text(member.name).font(.headline).foregroundStyle(Brand.ink)
                                        Text(member.relation?.label(lang) ?? "").font(.subheadline).foregroundStyle(Brand.ink3)
                                    }
                                    Spacer()
                                    if member.isPending {
                                        Button(lang.t("Allow", "Izinkan")) { Task { await model.allow(member) } }
                                            .buttonStyle(PillButtonStyle())
                                    } else {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.green).font(.title3)
                                    }
                                }
                                .padding(12)
                            }
                        }
                    }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                await model.refreshFamily()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}

/// Placeholder until puck pairing is built: pairing happens in the Puck tab.
struct PuckSetupButton: View {
    var onPaired: () -> Void
    @Environment(\.lang) private var lang

    var body: some View {
        Button {
            onPaired()
        } label: {
            Label(lang.t("Find puck", "Cari puck"), systemImage: "dot.radiowaves.left.and.right")
        }
        .buttonStyle(PrimaryButtonStyle())
    }
}
