import Foundation

/// State only: no event recording, permissions, or UI side effects.
struct UnlockGesture {
    static let holdDuration: TimeInterval = 2
    private(set) var startedAt: TimeInterval?

    mutating func keyDown(isUnlockKey: Bool, modifiersMatch: Bool, isRepeat: Bool, at time: TimeInterval) {
        guard isUnlockKey && modifiersMatch else { startedAt = nil; return }
        if !isRepeat && startedAt == nil { startedAt = time }
    }

    mutating func keyUp(isUnlockKey: Bool) { if isUnlockKey { startedAt = nil } }
    mutating func modifiersChanged(match: Bool) { if !match { startedAt = nil } }
    func isComplete(at time: TimeInterval) -> Bool {
        guard let startedAt else { return false }
        return time - startedAt >= Self.holdDuration
    }
}
