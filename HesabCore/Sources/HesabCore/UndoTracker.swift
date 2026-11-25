import Foundation

/// «برگرداندن» after a change (audit 2026-11, critical #2).
///
/// An undo puts back the whole state from before the change. That is only right while nothing else has changed
/// since; otherwise the newer change would silently disappear too. So every change gets a number, an undo
/// remembers the number of its own change, and it is refused once any later change has been made. A change that
/// offers no undo of its own also clears the one on offer.
public struct UndoTracker<State> {
    public struct Offer {
        public let id: UUID
        public let message: String
        public let previous: State
        fileprivate let version: Int
    }

    public private(set) var version = 0
    public private(set) var offer: Offer?

    public init() {}

    /// Call after every saved change. `message` = this change can be undone (shown on the undo bar).
    @discardableResult
    public mutating func didChange(previous: State, message: String?) -> Offer? {
        version += 1
        offer = message.map { Offer(id: UUID(), message: $0, previous: previous, version: version) }
        return offer
    }

    /// The state to put back, only if nothing has changed since the offered change; the offer is used up either way.
    public mutating func takeUndo() -> State? {
        guard let o = offer else { return nil }
        offer = nil
        return o.version == version ? o.previous : nil
    }

    /// The offer expired (its time ran out) — only if it is still that same offer.
    public mutating func expire(_ id: UUID) {
        if offer?.id == id { offer = nil }
    }

    /// Everything was reloaded or replaced (import, reset): no undo may reach back past it.
    public mutating func invalidate() {
        version += 1
        offer = nil
    }
}
