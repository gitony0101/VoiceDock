#!/usr/bin/swift
import Foundation

// VoiceDock Restart Helper — embedded executable
// Usage: voice-dock-restart-helper <bundle-path> <old-pid>

let args = CommandLine.arguments
if args.count < 3 {
    print("Usage: voice-dock-restart-helper <bundle-path> <old-pid>")
    exit(1)
}

let bundlePath = args[1]
let oldPID = Int(args[2]) ?? 0

if oldPID > 0 {
    var attempts = 0
    let maxAttempts = 60 // ~30 seconds
    while attempts < maxAttempts {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-p", String(oldPID), "-o", "pid="]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            break // PID not found = process gone
        }
        attempts += 1
        Thread.sleep(forTimeInterval: 0.5)
    }
}

// Launch using /usr/bin/open -n with exact bundle path (no shell interpolation of path)
let openTask = Process()
openTask.executableURL = URL(fileURLWithPath: "/usr/bin/open")
openTask.arguments = ["-n", bundlePath]
try? openTask.run()
openTask.waitUntilExit()
