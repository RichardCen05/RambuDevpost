import AVFoundation
import Foundation

/// Reads warnings and verdicts aloud on the parent's phone when "Read alerts aloud" is on.
/// Each warning level and each verdict is spoken once.
@MainActor
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechService()

    private let synthesizer = AVSpeechSynthesizer()
    private var spoken: Set<String> = []

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, lang: Lang) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: lang == .en ? "en-US" : "id-ID")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        synthesizer.speak(utterance)
    }

    /// Looks at the newest alert and speaks it if it is new to this phone and still relevant.
    func announceParentUpdates(_ model: AppModel) {
        guard model.role == .parent, model.settings.readAloud, let alert = model.alerts.first else { return }
        guard let (key, text) = Self.announcement(for: alert, lang: model.lang) else { return }
        guard spoken.insert(key).inserted else { return }
        speak(text, lang: model.lang)
    }

    /// What to say for an alert, keyed so the same message is never repeated. Nil when there is nothing fresh.
    nonisolated static func announcement(for alert: FamilyAlert, lang: Lang, now: Date = .now) -> (key: String, text: String)? {
        if let decision = alert.decision {
            guard !alert.callEnded || now.timeIntervalSince(decision.at) < 180 else { return nil }
            return ("verdict-\(alert.id)", alert.verdictSentence(lang) ?? "")
        }
        guard alert.level != .low else { return nil }
        guard !alert.callEnded || now.timeIntervalSince(alert.raisedAt) < 180 else { return nil }
        return ("warning-\(alert.id)-\(alert.level.rawValue)", "\(alert.level.label(lang)). \(alert.parentHeadline(lang)).")
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
