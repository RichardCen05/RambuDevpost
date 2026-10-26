import SwiftUI

// Practice runs are drawn entirely in the app: no backend calls, no pushes, no History entries.

/// Parent's last onboarding step: a pretend incoming call, then a pretend warning to tap.
struct ParentPracticeView: View {
    var onDone: () -> Void
    @Environment(\.lang) private var lang
    @State private var phase: Phase = .ringing
    @State private var declinedOnce = false
    @State private var seconds = 0

    enum Phase { case ringing, answered, done }

    private let callTop = Color(hex: 0x2E3836)
    private let callBottom = Color(hex: 0x141A19)

    var body: some View {
        ZStack {
            LinearGradient(colors: [callTop, callBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text(lang.t("PRACTICE", "LATIHAN"))
                        .font(.caption.weight(.heavy))
                        .tracking(1)
                        .foregroundStyle(Brand.amberInk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Brand.amber))
                    Spacer()
                    Button(lang.t("End practice", "Akhiri latihan"), action: onDone)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 40)
                        .background(Capsule().fill(.white.opacity(0.15)))
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                if phase == .answered {
                    Button { withAnimation(.spring) { phase = .done } } label: {
                        SampleNotification(
                            title: lang.t("Danger: possible scam", "Bahaya: kemungkinan penipuan"),
                            detail: lang.t("Be careful. Don't transfer money or share codes.",
                                           "Hati-hati. Jangan transfer uang atau memberi kode.")
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer(minLength: 24)

                Image(systemName: "person.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 110, height: 110)
                    .background(Circle().fill(.white.opacity(0.12)))
                Text(lang.t("Unknown number", "Nomor tidak dikenal"))
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 16)
                Text(phase == .ringing ? lang.t("Incoming call", "Panggilan masuk") : clock)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 4)

                Spacer(minLength: 24)

                bubble
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)

                if phase == .ringing {
                    HStack {
                        callButton(symbol: "phone.down.fill", color: Brand.red, label: lang.t("Decline", "Tolak")) {
                            declinedOnce = true
                        }
                        Spacer()
                        callButton(symbol: "phone.fill", color: Brand.green, label: lang.t("Answer", "Jawab")) {
                            withAnimation(.spring) { phase = .answered }
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.bottom, 32)
                } else {
                    Color.clear.frame(height: 110)
                }
            }

            if phase == .done { success.transition(.opacity) }
        }
        .task(id: phase) {
            guard phase == .answered else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                seconds += 1
            }
        }
    }

    private var clock: String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }

    private var bubble: some View {
        let text: String = switch phase {
        case .ringing where declinedOnce:
            lang.t("For this practice, tap Answer.", "Untuk latihan ini, tekan Jawab.")
        case .ringing:
            lang.t("There is a call from an unknown number. Tap Answer.", "Ada telepon dari nomor tidak dikenal. Tekan Jawab.")
        default:
            lang.t("Rambu sent a warning. Tap the notification.", "Rambu mengirim peringatan. Ketuk notifikasinya.")
        }
        return HStack(spacing: 10) {
            Image("mascot-wave").resizable().scaledToFit().frame(width: 40, height: 46)
            Text(text)
                .font(.body.weight(.medium))
                .foregroundStyle(Brand.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white))
    }

    private func callButton(symbol: String, color: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(color))
                Text(label).font(.subheadline.weight(.medium)).foregroundStyle(.white)
            }
        }
        .accessibilityLabel(label)
    }

    private var success: some View {
        VStack(spacing: 16) {
            Spacer()
            Image("mascot-happy-safe").resizable().scaledToFit().frame(height: 170)
            Text(lang.t("Well done!", "Bagus!"))
                .font(Brand.title())
                .foregroundStyle(Brand.ink)
            Text(lang.t("This is how Rambu warns you during a real call. Your family gets the same warning.",
                        "Begini cara Rambu memperingatkan Anda saat telepon sungguhan. Keluarga juga menerima peringatan yang sama."))
                .font(.body)
                .foregroundStyle(Brand.ink2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
            Button(lang.t("Go to Home", "Ke Beranda"), action: onDone)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.canvas.ignoresSafeArea())
    }
}

/// Caregiver's last onboarding step: decide on a sample alert marked Example.
struct CaregiverPracticeStep: View {
    var onDone: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.lang) private var lang
    @State private var choice: Bool?  // true = scam

    var body: some View {
        let parent = model.family?.parent?.name ?? "Ratna"
        StepScaffold(
            step: 4, total: 4,
            title: lang.t("Make a decision", "Buat keputusan"),
            subtitle: lang.t("This is what an alert looks like. Try answering it.", "Seperti inilah peringatan. Coba jawab."),
            onBack: nil
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image("mascot-stop-danger").resizable().scaledToFit().frame(width: 52, height: 60)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lang.t("EXAMPLE", "CONTOH"))
                            .font(.caption2.weight(.heavy))
                            .tracking(1)
                            .foregroundStyle(Brand.amberInk)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Brand.amber))
                        Text(lang.t("\(parent) may be getting scammed", "\(parent) mungkin sedang ditipu"))
                            .font(.headline)
                            .foregroundStyle(Brand.ink)
                    }
                }
                QuoteCard(
                    evidence: Evidence(
                        quote: lang.t("Read me the code we just sent, so we can stop the transfer.",
                                      "Bacakan kode yang baru kami kirim, supaya transfernya bisa kami hentikan."),
                        signals: []
                    ),
                    tint: Brand.red
                )
                Label(lang.t("Flagged by Rambu: \(Signal.secretCode.title(lang))", "Ditandai Rambu: \(Signal.secretCode.title(lang))"),
                      systemImage: Signal.secretCode.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.redInk)

                if let choice {
                    Label(
                        choice
                            ? lang.t("In a real alert, \(parent) would be told right away to hang up.",
                                     "Di peringatan sungguhan, \(parent) langsung diminta menutup telepon.")
                            : lang.t("In a real alert, \(parent) would be told the call looks safe.",
                                     "Di peringatan sungguhan, \(parent) diberi tahu bahwa panggilan terlihat aman."),
                        systemImage: "info.circle.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(Brand.ink2)
                    .padding(.top, 4)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white))
        } footer: {
            if choice == nil {
                HStack(spacing: 12) {
                    Button { withAnimation { choice = false } } label: {
                        Label(lang.t("Safe", "Aman"), systemImage: "checkmark")
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: Brand.green))
                    Button { withAnimation { choice = true } } label: {
                        Label(lang.t("Scam", "Penipuan"), systemImage: "hand.raised.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: Brand.red))
                }
            } else {
                Button(lang.t("Go to Home", "Ke Beranda"), action: onDone)
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }
}
