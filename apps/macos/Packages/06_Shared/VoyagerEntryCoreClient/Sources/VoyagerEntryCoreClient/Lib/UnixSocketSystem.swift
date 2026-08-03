import Darwin
import Foundation

enum UnixSocketCallResult: Equatable {
    case success(Int32)
    case failure(Int32)
}

enum UnixSocketPairResult: Equatable {
    case success(read: Int32, write: Int32)
    case failure(Int32)
}

enum UnixSocketReceiveResult: Equatable {
    case data(Data)
    case eof
    case failure(Int32)
}

enum UnixSocketPollResult: Equatable {
    case ready(networkEvents: Int16, wakeEvents: Int16)
    case timedOut
    case failure(Int32)
}

protocol UnixSocketSystem: Sendable {
    func makeSocket() -> UnixSocketCallResult
    func setNoSigPipe(_ fd: Int32) -> UnixSocketCallResult
    func makeWakePipe() -> UnixSocketPairResult
    func connect(_ fd: Int32, address: sockaddr_un, length: socklen_t) -> UnixSocketCallResult
    func socketError(_ fd: Int32) -> UnixSocketCallResult
    func send(_ fd: Int32, bytes: Data) -> UnixSocketCallResult
    func shutdownWrite(_ fd: Int32) -> UnixSocketCallResult
    func receive(_ fd: Int32, maximumBytes: Int) -> UnixSocketReceiveResult
    func poll(networkFD: Int32, events: Int16, wakeFD: Int32, timeoutMilliseconds: Int32) -> UnixSocketPollResult
    func signalWake(_ fd: Int32)
    func drainWake(_ fd: Int32)
    func close(_ fd: Int32)
}

struct DarwinUnixSocketSystem: UnixSocketSystem {
    func makeSocket() -> UnixSocketCallResult {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .failure(errno) }
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
            let errorNumber = errno
            Darwin.close(fd)
            return .failure(errorNumber)
        }
        return .success(fd)
    }

    func setNoSigPipe(_ fd: Int32) -> UnixSocketCallResult {
        var enabled: Int32 = 1
        let result = withUnsafePointer(to: &enabled) {
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, $0, socklen_t(MemoryLayout<Int32>.size))
        }
        return result == 0 ? .success(0) : .failure(errno)
    }

    func makeWakePipe() -> UnixSocketPairResult {
        var descriptors = [Int32](repeating: -1, count: 2)
        guard Darwin.pipe(&descriptors) == 0 else { return .failure(errno) }
        for fd in descriptors {
            let flags = fcntl(fd, F_GETFL)
            guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
                let errorNumber = errno
                Darwin.close(descriptors[0])
                Darwin.close(descriptors[1])
                return .failure(errorNumber)
            }
        }
        return .success(read: descriptors[0], write: descriptors[1])
    }

    func connect(_ fd: Int32, address: sockaddr_un, length: socklen_t) -> UnixSocketCallResult {
        var mutableAddress = address
        let result = withUnsafePointer(to: &mutableAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, length)
            }
        }
        return result == 0 ? .success(0) : .failure(errno)
    }

    func socketError(_ fd: Int32) -> UnixSocketCallResult {
        var value: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        let result = withUnsafeMutablePointer(to: &value) {
            getsockopt(fd, SOL_SOCKET, SO_ERROR, $0, &length)
        }
        return result == 0 ? .success(value) : .failure(errno)
    }

    func send(_ fd: Int32, bytes: Data) -> UnixSocketCallResult {
        let result = bytes.withUnsafeBytes {
            Darwin.send(fd, $0.baseAddress, $0.count, 0)
        }
        return result >= 0 ? .success(Int32(result)) : .failure(errno)
    }

    func shutdownWrite(_ fd: Int32) -> UnixSocketCallResult {
        let result = Darwin.shutdown(fd, SHUT_WR)
        return result == 0 ? .success(0) : .failure(errno)
    }

    func receive(_ fd: Int32, maximumBytes: Int) -> UnixSocketReceiveResult {
        var buffer = [UInt8](repeating: 0, count: maximumBytes)
        let result = Darwin.recv(fd, &buffer, maximumBytes, 0)
        if result > 0 {
            return .data(Data(buffer.prefix(result)))
        }
        return result == 0 ? .eof : .failure(errno)
    }

    func poll(
        networkFD: Int32,
        events: Int16,
        wakeFD: Int32,
        timeoutMilliseconds: Int32,
    ) -> UnixSocketPollResult {
        var descriptors = [
            pollfd(fd: networkFD, events: events, revents: 0),
            pollfd(fd: wakeFD, events: Int16(POLLIN), revents: 0),
        ]
        let result = Darwin.poll(&descriptors, nfds_t(descriptors.count), timeoutMilliseconds)
        if result > 0 {
            return .ready(networkEvents: descriptors[0].revents, wakeEvents: descriptors[1].revents)
        }
        return result == 0 ? .timedOut : .failure(errno)
    }

    func signalWake(_ fd: Int32) {
        var byte: UInt8 = 1
        _ = Darwin.write(fd, &byte, 1)
    }

    func drainWake(_ fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 32)
        while Darwin.read(fd, &buffer, buffer.count) > 0 {}
    }

    func close(_ fd: Int32) {
        Darwin.close(fd)
    }
}
