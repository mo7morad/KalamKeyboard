#if DEBUG
import os
import UIKit

/// Debug-only readout (SPEC §11): phys_footprint, os_proc_available_memory headroom, and the last
/// suggestion latency, which Phase 5 sets.
final class DebugOverlay: UILabel {
    var latencyMs: Double? { didSet { refresh() } }
    private var timer: Timer?
    private static let log = Logger(subsystem: "com.morad.kalam.keyboard", category: "memory")

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = .monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        textColor = .systemRed
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        timer?.invalidate()
        guard window != nil else { return }
        refresh()
        Self.log.info("footprint \(Self.footprintMB, format: .fixed(precision: 1)) MB, headroom \(Self.headroomMB, format: .fixed(precision: 1)) MB")
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        let latency = latencyMs.map { String(format: "%.1f ms", $0) } ?? "– ms"
        text = String(format: "%.1f MB · %.1f free · ", Self.footprintMB, Self.headroomMB) + latency
    }

    static var footprintMB: Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    static var headroomMB: Double { Double(os_proc_available_memory()) / 1_048_576 }
}
#endif
