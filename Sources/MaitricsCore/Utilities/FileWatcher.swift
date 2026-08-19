import Foundation

public final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let path: String
    private let debounceInterval: TimeInterval
    private let onChange: () -> Void
    private var pendingWork: DispatchWorkItem?

    /// - Parameter debounceInterval: writers rewrite `stats-cache.json` in several
    ///   bursts, and each raw event used to kick off a full transcript scan.
    ///   Coalescing them collapses a burst into a single refresh.
    public init(path: String, debounceInterval: TimeInterval = 1.5, onChange: @escaping () -> Void) {
        self.path = path
        self.debounceInterval = debounceInterval
        self.onChange = onChange
    }

    deinit { stop() }

    public func start() {
        stop()
        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            startWatchingParent()
            return
        }
        let fd = fileDescriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = self.source?.data ?? []
            if flags.contains(.rename) || flags.contains(.delete) {
                // The file was replaced (atomic write) — our descriptor now points
                // at a dead inode, so re-attach before reporting the change.
                self.start()
            }
            self.scheduleChange()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.source = source
    }

    public func stop() {
        pendingWork?.cancel()
        pendingWork = nil
        if let source {
            source.cancel()
            self.source = nil
        }
        // FD is closed by the cancel handler — don't double-close
        fileDescriptor = -1
    }

    private func scheduleChange() {
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingWork = nil
            self?.onChange()
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    private func startWatchingParent() {
        let parentPath = (path as NSString).deletingLastPathComponent
        fileDescriptor = open(parentPath, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }
        let fd = fileDescriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            // The parent directory sees every unrelated write in `~/.claude`, so
            // only react once the watched file itself shows up.
            guard FileManager.default.fileExists(atPath: self.path) else { return }
            self.start()
            self.scheduleChange()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.source = source
    }
}
