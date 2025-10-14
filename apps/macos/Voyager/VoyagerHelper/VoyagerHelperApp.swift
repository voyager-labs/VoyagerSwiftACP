import Foundation

@main
class VoyagerHelperApp {
    static func main() {
        _ = BackendManagerDotenv() // 백엔드 관리자 초기화 및 백엔드 시작
        RunLoop.current.run() // 헬퍼 앱을 백그라운드에서 계속 실행
    }
}
