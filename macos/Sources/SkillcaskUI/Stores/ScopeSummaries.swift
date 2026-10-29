import Foundation
import Observation
import SkillcaskCore
import SkillcaskDomain

/// The sidebar badges of the scopes nobody opened yet (Flow-F5 "computed for every open project"): the projects,
/// and My Skills when another scope opened first. One `status --json` per scope in the background, at most `limit`
/// at a time, its `Attention` kept here. Only `status`: it is local and fast, while `outdated` stays an explicit
/// Check, so such a badge counts the red and amber rows `status` alone knows and no blue updates until the
/// scope is opened and checked. A failed read is not repeated until the next launch or binary change. Once a scope
/// has a `ScopeStore`, its snapshot is the badge (`AppStore.attention(for:)`) and this entry is not read. No
/// `ScopeStore` is built here: a summary is one document and one count, nothing the window would keep.
@MainActor @Observable public final class ScopeSummaries {
    /// How many `status` reads run at once.
    public static let limit = 3

    /// The attention of every summarized scope.
    public private(set) var attention: [Scope: Attention] = [:]

    /// The scopes waiting for a free slot, in sidebar order.
    @ObservationIgnored private var pending: [Scope] = []
    /// The scopes whose read failed: not asked again until `forget` or `reset` (the next launch or binary change);
    /// opening one builds its store, whose own refresh is the retry.
    @ObservationIgnored private var failed: Set<Scope> = []
    /// The reads in flight, each with an identity so a forgotten scope's late end changes nothing.
    @ObservationIgnored private var running: [Scope: (id: UUID, task: Task<Void, Never>)] = [:]
    @ObservationIgnored private var source: (client: any CLIClient, capabilities: Capabilities)?

    public init() {}

    /// Queues a `status` read for every scope of `scopes` that has no summary and none queued or running; reads
    /// through `client`. Returns at once: the reads run in the background.
    public func summarize(_ scopes: [Scope], client: any CLIClient, capabilities: Capabilities) {
        source = (client, capabilities)
        for scope in scopes
        where attention[scope] == nil && running[scope] == nil && !pending.contains(scope) && !failed.contains(scope) {
            pending.append(scope)
        }
        startNext()
    }

    /// The project left the sidebar: its read is cancelled (or never starts) and its badge dropped.
    public func forget(_ scope: Scope) {
        pending.removeAll { $0 == scope }
        running.removeValue(forKey: scope)?.task.cancel()
        attention[scope] = nil
        failed.remove(scope)
        startNext()
    }

    /// The CLI changed: every read is cancelled and every summary dropped, so the next `summarize` asks the new one.
    public func reset() {
        pending.removeAll()
        for (_, run) in running {
            run.task.cancel()
        }
        running.removeAll()
        attention.removeAll()
        failed.removeAll()
        source = nil
    }

    /// Tests: suspends until nothing is queued or running.
    func settle() async {
        while let run = running.values.first {
            await run.task.value
        }
    }

    /// Whether a read is queued or running for `scope`.
    func isPending(_ scope: Scope) -> Bool {
        running[scope] != nil || pending.contains(scope)
    }

    // MARK: - Reads

    private func startNext() {
        guard let source else { return }
        while running.count < Self.limit, !pending.isEmpty {
            let scope = pending.removeFirst()
            let id = UUID()
            let task = Task { [weak self] in
                let attention = await Self.read(scope, client: source.client, capabilities: source.capabilities)
                self?.finish(scope, id: id, attention: attention)
            }
            running[scope] = (id, task)
        }
    }

    private func finish(_ scope: Scope, id: UUID, attention: Attention?) {
        guard running[scope]?.id == id else { return }
        running[scope] = nil
        // Cancelled by `forget` or `reset`: no badge, no failure remembered.
        if !Task.isCancelled {
            if let attention {
                self.attention[scope] = attention
            } else {
                failed.insert(scope)
            }
        }
        startNext()
    }

    /// `status --json` in `scope`, as the badge counts it; nil when the read failed or was cancelled (no badge).
    private nonisolated static func read(
        _ scope: Scope, client: any CLIClient, capabilities: Capabilities
    ) async -> Attention? {
        do {
            let invocation = try Invocation(.status, in: scope, capabilities: capabilities)
            let status = try await client.document(StatusDocument.self, for: invocation)
            return ScopeSnapshot(status: status, audit: nil, doctor: nil, outdated: nil).attention
        } catch {
            return nil
        }
    }
}
