import Foundation

/// Works out which member of a cycle comes next. Kept apart from the windows
/// it moves between so the order can be reasoned about on its own.
enum CycleOrder {
    /// - Parameters:
    ///   - members: the cycle, in the order it should be walked.
    ///   - current: the member in front now, if it belongs to this cycle.
    ///   - loops: whether stepping off the end returns to the other end.
    /// - Returns: the member to switch to, or nothing when the cycle is empty
    ///   or the step would fall off an end that does not loop.
    static func next(in members: [String], from current: String?,
                     forward: Bool, loops: Bool) -> String? {
        guard !members.isEmpty else { return nil }
        guard let current, let index = members.firstIndex(of: current) else {
            return forward ? members.first : members.last
        }

        let step = index + (forward ? 1 : -1)
        if step >= 0 && step < members.count { return members[step] }
        guard loops else { return nil }
        return forward ? members.first : members.last
    }
}
