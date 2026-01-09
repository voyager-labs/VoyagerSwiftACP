import Darwin
import Foundation

struct PortReservationService {
    enum Error: Swift.Error, Equatable {
        case socketFailed
        case bindFailed
        case socketNameFailed
    }

    nonisolated func reserve() throws -> Int {
        let socketFd = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFd >= 0 else {
            throw Error.socketFailed
        }
        defer {
            close(socketFd)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(0).bigEndian
        address.sin_addr = in_addr(s_addr: INADDR_ANY)

        let bindResult = withUnsafePointer(to: &address) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socketFd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            throw Error.bindFailed
        }

        var sockLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        var outAddress = sockaddr_in()
        let getResult = withUnsafeMutablePointer(to: &outAddress) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(socketFd, $0, &sockLen)
            }
        }

        guard getResult == 0 else {
            throw Error.socketNameFailed
        }

        return Int(UInt16(bigEndian: outAddress.sin_port))
    }

    nonisolated func canConnect(host: String, port: Int) -> Bool {
        let targetHost = host == "0.0.0.0" ? "127.0.0.1" : host
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil,
        )

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(targetHost, String(port), &hints, &result)
        guard status == 0, let result else {
            return false
        }
        defer {
            freeaddrinfo(result)
        }

        var current: UnsafeMutablePointer<addrinfo>? = result
        while let info = current {
            let socketFd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
            if socketFd >= 0 {
                if connect(socketFd, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 {
                    close(socketFd)
                    return true
                }
                close(socketFd)
            }
            current = info.pointee.ai_next
        }

        return false
    }

    nonisolated func verifyListening(
        host: String,
        port: Int,
        isRunning: @Sendable () async -> Bool,
        attempts: Int = 10,
        delay: TimeInterval = 1,
        shouldStop: @Sendable () -> Bool,
    ) async -> Bool {
        for _ in 0 ..< attempts {
            if shouldStop() || Task.isCancelled {
                return false
            }
            if await isRunning(), canConnect(host: host, port: port) {
                return true
            }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        return false
    }
}
