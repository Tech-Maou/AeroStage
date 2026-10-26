import AeroStageCore
import Foundation

/// Accepts commands from the `aerostage` CLI over a Unix socket.
final class CommandServer: @unchecked Sendable {
    typealias Handler = @Sendable (IPCRequest) async -> IPCResponse

    private let path = IPC.socketPath
    private let queue = DispatchQueue(label: "AeroStage.CommandServer")
    private var listener: Int32 = -1
    private var source: DispatchSourceRead?

    func start(handler: @escaping Handler) throws {
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        unlink(path)

        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw IPCError.socket(String(cString: strerror(errno))) }
        var address = try IPC.makeAddress(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(listener, 16) == 0 else {
            throw IPCError.socket(String(cString: strerror(errno)))
        }
        chmod(path, 0o600)

        let listeningSocket = listener
        let source = DispatchSource.makeReadSource(fileDescriptor: listeningSocket, queue: queue)
        source.setEventHandler {
            let client = accept(listeningSocket, nil, nil)
            guard client >= 0 else { return }
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var noSigPipe: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

            guard let line = IPC.readLine(client),
                  let request = try? JSONDecoder().decode(IPCRequest.self, from: line)
            else {
                Self.reply(.failure("Invalid request"), to: client)
                return
            }
            Task {
                Self.reply(await handler(request), to: client)
            }
        }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
        if listener >= 0 { close(listener) }
        listener = -1
        unlink(path)
    }

    private static func reply(_ response: IPCResponse, to client: Int32) {
        if var data = try? JSONEncoder().encode(response) {
            data.append(0x0A)
            try? IPC.writeAll(client, data)
        }
        close(client)
    }
}
