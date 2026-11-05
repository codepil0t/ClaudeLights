import AppKit
import Darwin

/// Finds the GUI app (Terminal, iTerm, VS Code, …) that hosts a process.
enum ProcessTree {
    static func parent(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let ppid = info.kp_eproc.e_ppid
        return ppid > 0 ? ppid : nil
    }

    static func hostingApp(of pid: pid_t) -> NSRunningApplication? {
        var current: pid_t? = pid
        var steps = 0
        while let p = current, p > 1, steps < 32 {
            if let app = NSRunningApplication(processIdentifier: p), app.activationPolicy == .regular {
                return app
            }
            current = parent(of: p)
            steps += 1
        }
        return nil
    }
}
