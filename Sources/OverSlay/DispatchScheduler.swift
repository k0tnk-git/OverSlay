import Foundation
import OverSlayCore

final class DispatchScheduler: ActionScheduler {
    @discardableResult
    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> Cancellable {
        let item = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: item)
        return DispatchToken(item)
    }

    private final class DispatchToken: Cancellable {
        private let item: DispatchWorkItem
        init(_ item: DispatchWorkItem) { self.item = item }
        func cancel() { item.cancel() }
    }
}
