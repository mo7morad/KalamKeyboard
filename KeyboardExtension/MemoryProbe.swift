#if DEBUG
import os
import UIKit

/// Debug-only footprint probe (SPEC §11): logs phys_footprint and the os_proc_available_memory
/// headroom on each appear. Read it in Console.app, category "memory". No on-screen readout (Moe).
enum MemoryProbe {
    private static let log = Logger(subsystem: "com.morad.kalam.keyboard", category: "memory")

    static func logFootprint() {
        log.info("footprint \(footprintMB, format: .fixed(precision: 1)) MB, headroom \(headroomMB, format: .fixed(precision: 1)) MB")
    }

    private static var footprintMB: Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    private static var headroomMB: Double { Double(os_proc_available_memory()) / 1_048_576 }
}
#endif
