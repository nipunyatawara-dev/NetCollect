import SwiftUI
import NetCollectCore

guard SingleInstanceGuard.shared.acquire() else {
    exit(EXIT_SUCCESS)
}

NetCollectApp.main()
