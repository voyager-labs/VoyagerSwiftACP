import Darwin
import Foundation

enum CodexExecProcessTerminator {
    /// SIGTERM 이후 제한 시간 안에 종료를 확인하고, 종료를 무시하면 SIGKILL로
    /// 에스컬레이션한다. 취소 호출자가 종료를 확인한 뒤에만 정산이 이어지도록 한다.
    static func stop(_ process: Process, graceInterval: TimeInterval = 2) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(graceInterval)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard process.isRunning else { return }
        kill(process.processIdentifier, SIGKILL)
    }
}
