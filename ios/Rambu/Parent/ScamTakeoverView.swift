import AVFoundation
import SwiftUI
import UIKit

/// Full-screen alarm on the parent's phone once a caregiver confirms a scam.
/// It is deliberately hard to ignore: flashing red, a looping alarm that plays even in silent mode,
/// continuous vibration, and a spoken "hang up" — until the parent taps "I hung up".
struct ScamTakeoverView: View {
    let alert: FamilyAlert
    @Environment(AppModel.self) private var model
    @Environment(\.lang) private var lang
    @State private var flash = false
    @State private var alarm = ScamAlarm()
    @State private var closing = false

    private var decider: String { alert.decision?.byName ?? "" }

    var body: some View {
        ZStack {
            (flash ? Brand.red : Brand.redInk)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true), value: flash)

            VStack(spacing: 22) {
                Spacer(minLength: 10)
                Image("mascot-stop-danger-dark")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 180)
                    .scaleEffect(flash ? 1.06 : 0.96)
                    .animation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true), value: flash)

                Text(lang.t("HANG UP NOW", "TUTUP TELEPON SEKARANG"))
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)

                Text(lang.t("\(decider) says this call is a scam.", "\(decider) bilang telepon ini penipuan."))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 10) {
                    Label(lang.t("Don't share any code or PIN", "Jangan berikan kode atau PIN"), systemImage: "key.slash")
                    Label(lang.t("Don't send money", "Jangan kirim uang"), systemImage: "banknote")
                    Label(lang.t("Call the number on the back of your card", "Hubungi nomor di balik kartu Anda"), systemImage: "creditcard")
                }
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Brand.redInk)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white))

                Spacer(minLength: 10)

                Button {
                    closing = true
                    alarm.stop()
                    Task { await model.acknowledge(alert) }
                } label: {
                    Label(lang.t("I hung up", "Saya sudah tutup telepon"), systemImage: "phone.down.fill")
                        .font(.system(.title3, design: .rounded).weight(.heavy))
                        .frame(maxWidth: .infinity, minHeight: 68)
                        .foregroundStyle(Brand.red)
                        .background(Capsule().fill(.white))
                }
                .disabled(closing)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .interactiveDismissDisabled()
        .onAppear {
            flash = true
            alarm.start(spoken: lang.t("Hang up now. \(decider) says this call is a scam.",
                                       "Tutup telepon sekarang. \(decider) bilang ini penipuan."),
                        voice: lang == .en ? "en-US" : "id-ID")
        }
        .onDisappear { alarm.stop() }
    }
}

/// Looping alarm sound, repeated vibration, and a repeated spoken warning.
@MainActor
final class ScamAlarm {
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private let speaker = AVSpeechSynthesizer()
    private var tick = 0

    func start(spoken: String, voice: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.duckOthers])  // plays even with the silent switch on
        try? session.setActive(true)
        if let url = Bundle.main.url(forResource: "rambu-urgent", withExtension: "caf") {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1
            player?.volume = 1
            player?.play()
        }
        let haptics = UINotificationFeedbackGenerator()
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                haptics.notificationOccurred(.error)
                self.tick += 1
                if self.tick % 8 == 1 {  // every ~6 s, between alarm loops
                    let utterance = AVSpeechUtterance(string: spoken)
                    utterance.voice = AVSpeechSynthesisVoice(language: voice)
                    utterance.volume = 1
                    self.speaker.speak(utterance)
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        speaker.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
