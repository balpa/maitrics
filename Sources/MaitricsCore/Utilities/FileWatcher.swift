import Foundation

public final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let path: String
    private let onChange: () -> Void

    public init(path: String, onChange: @escaping () -> Void) {
        self.path = path
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
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.onChange() }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.source = source
    }

    public func stop() {
        if let source {
            source.cancel()
            self.source = nil
        }
        // FD is closed by the cancel handler — don't double-close
        fileDescriptor = -1
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
            if FileManager.default.fileExists(atPath: self.path) {
                self.stop()
                self.start()
                self.onChange()
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.source = source
    }
}
