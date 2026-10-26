import Foundation

enum Role: String, Codable, Sendable {
    case parent, caregiver
}

struct Invite: Codable, Equatable, Sendable {
    let code: String
    let expiresAt: Date
}

struct Member: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let role: Role
    let status: String
    let name: String
    let relationship: String?
    let language: String

    var isPending: Bool { status == "pending" }
    var relation: Relationship? { relationship.flatMap(Relationship.init(rawValue:)) }
}

struct PuckInfo: Codable, Equatable, Sendable {
    let id: String
    let online: Bool
    let lastSeenAt: Date?
    let firmware: String?
}

/// The parent's call that the backend is listening to right now.
struct ActiveCall: Codable, Equatable, Sendable {
    let sessionId: String
    let startedAt: Date
    let level: Risk
    let alertId: String?
}

struct Evidence: Codable, Hashable, Sendable {
    let quote: String
    let signals: [Signal]
}

struct Decision: Codable, Equatable, Sendable {
    let verdict: String  // "scam" or "safe"
    let byId: String
    let byName: String
    let at: Date

    var isScam: Bool { verdict == "scam" }
}

struct Recipient: Codable, Equatable, Sendable {
    let id: String
    let name: String
}

/// A warning about one call, sent to the parent and every caregiver.
struct FamilyAlert: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let sessionId: String
    let parentName: String
    let level: Risk
    let signals: [Signal]
    let evidence: [Evidence]
    let raisedAt: Date
    let callEnded: Bool
    let decision: Decision?
    let recipients: [Recipient]
    /// The parent confirmed they hung up after a scam verdict.
    var acknowledged: Bool? = nil

    /// A scam verdict the parent hasn't confirmed yet, recent enough to still matter.
    var needsHangUp: Bool {
        guard let decision, decision.isScam, acknowledged != true else { return false }
        return Date.now.timeIntervalSince(decision.at) < 10 * 60
    }
}

struct DecisionResult: Codable, Sendable {
    let alert: FamilyAlert
    let accepted: Bool
}

/// One finished (or ongoing) call in History.
struct CallRecord: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Int?
    /// "listening", "completed", "no_speech", or "failed"
    let status: String
    let level: Risk
    let signals: [Signal]
    let evidence: [Evidence]
    let decision: Decision?
    let failureReason: String?
    /// Masked transcript; only in the parent's call detail.
    let transcript: String?

    var couldNotAssess: Bool { status == "no_speech" || status == "failed" }
}

struct Family: Codable, Equatable, Sendable {
    let familyId: String
    let me: Member
    let members: [Member]
    let invite: Invite?
    let puck: PuckInfo?
    let activeCall: ActiveCall?

    var parent: Member? { members.first { $0.role == .parent } }
    var caregivers: [Member] { members.filter { $0.role == .caregiver && !$0.isPending } }
    var pending: [Member] { members.filter(\.isPending) }
}

struct CreateFamilyResponse: Codable, Sendable {
    let deviceToken: String
    let deviceId: String
    let familyId: String
    let invite: Invite
}

struct JoinResponse: Codable, Sendable {
    let deviceToken: String
    let deviceId: String
    let status: String
}

struct PuckCredentials: Codable, Sendable {
    let puckId: String
    let puckToken: String
}
