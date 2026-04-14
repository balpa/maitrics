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
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.onChange() }
        source.setCancelHandler { [weak self] in
            guard let self, self.fileDescriptor >= 0 else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }
        source.resume()
        self.source = source
    }

    public func stop() {
        source?.cancel()
        source = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    private func startWatchingParent() {
        let parentPath = (path as NSString).deletingLastPathComponent
        fileDescriptor = open(parentPath, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
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
        source.setCancelHandler { [weak self] in
            guard let self, self.fileDescriptor >= 0 else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }
        source.resume()
        self.source = source
    }
}
