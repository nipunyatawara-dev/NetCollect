import Foundation
import Darwin

/// Prevents separate copies of NetCollect from collecting into the same database concurrently.
public final class SingleInstanceGuard: @unchecked Sendable {
    public static let shared = SingleInstanceGuard()

    private let lockURL: URL
    private var lockFileDescriptor: Int32 = -1
    private let lock = NSLock()

    public init(lockURL: URL? = nil) {
        if let lockURL {
            self.lockURL = lockURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let directory = appSupport.appendingPathComponent("NetCollect", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.lockURL = directory.appendingPathComponent("collector.lock")
        }
    }

    deinit {
        release()
    }

    public func acquire() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if lockFileDescriptor >= 0 { return true }

        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return false }
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
