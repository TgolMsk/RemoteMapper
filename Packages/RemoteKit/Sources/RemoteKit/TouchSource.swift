import CoreGraphics
import Foundation

public enum TouchSourceStatus: Equatable, Sendable {
    case idle
    case notFound
    case running
    case unavailable(String)
}

/// 触控面数据来源，实现为基于 MultitouchSupport 的 `TouchSurface`。
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
