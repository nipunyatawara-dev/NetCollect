import Foundation
import Darwin

/// Prevents separate copies of NetCollect from collecting into the same database concurrently.
public final class SingleInstanceGuard: @unchecked Sendable {
    public static let shared = SingleInstanceGuard()

    private let lockURL: URL
    private let usesDefaultDirectory: Bool
    private var lockFileDescriptor: Int32 = -1
    private let lock = NSLock()

    public init(lockURL: URL? = nil) {
        self.lockURL = lockURL ?? LocalStorage.directory.appending(path: "collector.lock")
        usesDefaultDirectory = lockURL == nil
    }

    deinit {
        release()
    }

    public func acquire() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if lockFileDescriptor >= 0 { return true }

        let descriptor: Int32
        do {
            if usesDefaultDirectory { try LocalStorage.prepareDirectory() }
            descriptor = try LocalStorage.openPrivateFile(at: lockURL.path, create: true)
        } catch {
            return false
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return false
        }

        lockFileDescriptor = descriptor
        return true
    }

    public func release() {
        lock.lock()
        defer { lock.unlock() }

        guard lockFileDescriptor >= 0 else { return }
        flock(lockFileDescriptor, LOCK_UN)
        close(lockFileDescriptor)
        lockFileDescriptor = -1
    }
}
