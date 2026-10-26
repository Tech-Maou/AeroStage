import Foundation

/// Commands from the `aerostage` CLI to the running app.
public enum IPCCommand: String, Codable, CaseIterable, Sendable {
    case focus, move, new, next, prev, toggle, settings, reload, quit, status
}

public struct IPCRequest: Codable, Sendable, Equatable {
    public var command: IPCCommand
    /// 1-based position for `focus` and `move`.
    public var position: Int?

    public init(command: IPCCommand, position: Int? = nil) {
        self.command = command
        self.position = position
    }
}

public struct IPCResponse: Codable, Sendable, Equatable {
    public var ok: Bool
    public var message: String?

    public init(ok: Bool, message: String? = nil) {
        self.ok = ok
        self.message = message
    }

    public static let success = IPCResponse(ok: true)
    public static func failure(_ message: String) -> IPCResponse { IPCResponse(ok: false, message: message) }
}

public enum IPCError: Error, CustomStringConvertible {
    case notRunning
    case socket(String)
    case protocolError(String)

    public var description: String {
        switch self {
        case .notRunning: "AeroStage is not running"
        case .socket(let detail): "Socket error: \(detail)"
        case .protocolError(let detail): "Protocol error: \(detail)"
        }
    }
}

/// Unix domain socket with one JSON line per request and response.
public enum IPC {
    public static var socketPath: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("AeroStage/control.sock").path
    }

    public static func send(_ request: IPCRequest, timeout: Int = 3) throws -> IPCResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw IPCError.socket(String(cString: strerror(errno))) }
        defer { close(fd) }

        var address = try makeAddress(socketPath)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw IPCError.notRunning }

        var tv = timeval(tv_sec: timeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var payload = try JSONEncoder().encode(request)
        payload.append(0x0A)
        try writeAll(fd, payload)

        guard let line = readLine(fd) else { throw IPCError.protocolError("no response") }
        return try JSONDecoder().decode(IPCResponse.self, from: line)
    }

    public static func makeAddress(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { throw IPCError.socket("path too long: \(path)") }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        return address
    }

    public static func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < buffer.count {
                let written = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                guard written > 0 else { throw IPCError.socket(String(cString: strerror(errno))) }
                offset += written
            }
        }
    }

    /// Reads up to the end of the line (without `\n`) or until the peer closes.
    public static func readLine(_ fd: Int32, limit: Int = 64 * 1024) -> Data? {
        var result = Data()
        var byte: UInt8 = 0
        while result.count < limit {
            let n = read(fd, &byte, 1)
            if n <= 0 { break }
            if byte == 0x0A { return result }
            result.append(byte)
        }
        return result.isEmpty ? nil : result
    }
}
