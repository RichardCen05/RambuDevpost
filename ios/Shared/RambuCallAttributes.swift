import ActivityKit
import Foundation

/// The parent's call status on the Lock Screen and Dynamic Island.
/// The backend starts, updates, and ends it with ActivityKit push notifications, so field names
/// here must match the payload in backend/rambu/push.py.
struct RambuCallAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// "listening", "low", "needs_review", "high_risk", or "scam"/"safe" once a caregiver decided.
        var level: String
        /// Short label, already in the parent's language ("Danger", "Bahaya").
        var title: String
        /// One sentence, already in the parent's language.
        var headline: String
        var decidedBy: String?
    }

    var parentName: String
    /// Unix seconds; a plain number keeps the push payload simple.
    var startedAt: Double

    var startDate: Date { Date(timeIntervalSince1970: startedAt) }
}

extension RambuCallAttributes.ContentState {
    var risk: Risk {
        switch level {
        case "high_risk", "scam": .highRisk
        case "needs_review": .needsReview
        default: .low
        }
    }

    var isListening: Bool { level == "listening" || level == "low" }

    var mascot: String {
        switch level {
        case "listening", "low": "mascot-calm"
        case "safe": "mascot-happy-safe"
        default: risk.mascot
        }
    }
}
