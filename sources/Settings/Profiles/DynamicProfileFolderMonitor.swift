//  DynamicProfileFolderMonitor.swift
//  Latterm

import CoreServices
import Foundation

/// Watches directory trees. Dynamic profiles may also reference individual
/// symlinks outside those trees, which the profile manager monitors separately.
@objc final class DynamicProfileFolderMonitor: NSObject {
    private final class Callback {
        let changed: () -> Void
        init(_ changed: @escaping () -> Void) { self.changed = changed }
    }

    private let stream: FSEventStreamRef

    @objc(initWithPaths:latency:changed:)
    init?(paths: [String], latency: TimeInterval, changed: @escaping () -> Void) {
        guard !paths.isEmpty else { return nil }
        let callback = Callback(changed)
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(callback).toOpaque(),
            retain: { UnsafeRawPointer(Unmanaged<Callback>.fromOpaque($0!).retain().toOpaque()) },
            release: { Unmanaged<Callback>.fromOpaque($0!).release() },
            copyDescription: nil)
        let created = withExtendedLifetime(callback) {
            FSEventStreamCreate(nil, { _, info, _, _, _, _ in
                guard let info else { return }
                Unmanaged<Callback>.fromOpaque(info).takeUnretainedValue().changed()
            }, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency, FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot))
        }
        guard let created else { return nil }
        FSEventStreamSetDispatchQueue(created, .main)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            return nil
        }
        stream = created
        super.init()
    }

    deinit {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
