import Darwin
import Foundation

enum LocalStorage {
    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "NetCollect", directoryHint: .isDirectory)
    }

    static func prepareDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { close(descriptor) }
        try restrictAccess(to: descriptor, type: S_IFDIR, permissions: 0o700)
    }

    static func openPrivateFile(at path: String, create: Bool) throws -> Int32 {
        let flags = O_RDWR | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK
        let descriptor = open(path, flags | (create ? O_CREAT : 0), 0o600)
        if !create && descriptor < 0 && errno == ENOENT { return -1 }
        guard descriptor >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        do {
            try restrictAccess(to: descriptor, type: S_IFREG, permissions: 0o600)
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    private static func restrictAccess(to descriptor: Int32, type: mode_t, permissions: mode_t) throws {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == type,
              metadata.st_uid == geteuid(),
              type == S_IFDIR || metadata.st_nlink == 1,
              fchmod(descriptor, permissions) == 0 else {
            throw CocoaError(.fileWriteNoPermission)
        }
    }
}
