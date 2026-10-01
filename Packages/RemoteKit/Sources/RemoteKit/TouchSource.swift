import CoreGraphics
import Foundation

public enum TouchSourceStatus: Equatable, Sendable {
    case idle
    case notFound
    case running
    case unavailable(String)
}

/// 触控面数据来源。官网版由 RemoteKitTouch 中基于 MultitouchSupport 的实现提供；
/// App Store 版不使用私有接口，没有触控来源。
public protocol TouchSource: AnyObject {
    var status: TouchSourceStatus { get }
    /// 当前接触中的触点，供界面实时显示
    var contacts: [TouchContact] { get }
    /// 触控面尺寸（毫米）
    var surfaceSize: CGSize? { get }
    var onFrame: ((TouchFrame) -> Void)? { get set }
    func start()
    func stop()
}

public extension TouchSource {
    var isRunning: Bool { status == .running }
}
