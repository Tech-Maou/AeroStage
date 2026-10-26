import AeroStageCore
import Foundation

signal(SIGPIPE, SIG_IGN)

let usage = """
Usage: aerostage <command>

  focus <n>    Switch to the stage at position n (n = count+1: new stage)
  move <n>     Move the focused window to the stage at position n
  new          Move the focused window to a new stage and follow it
  next | prev  Next or previous stage
  toggle       Show or hide the sidebar
  settings     Open settings
  reload       Re-sync state and the AeroSpace config
  status       Show status
  quit         Quit AeroStage
"""

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let first = args.first, let command = IPCCommand(rawValue: first) else {
    if args.first.map({ ["help", "-h", "--help"].contains($0) }) ?? true {
        print(usage)
        exit(0)
    }
    fail(usage, code: 2)
}

var position: Int?
if command == .focus || command == .move {
    guard args.count >= 2, let n = Int(args[1]), n >= 1 else { fail(usage, code: 2) }
    position = n
}

do {
    let response = try IPC.send(IPCRequest(command: command, position: position))
    if let message = response.message { print(message) }
    exit(response.ok ? 0 : 1)
} catch IPCError.notRunning {
    // Without the app, the shortcuts should still work like in plain AeroSpace.
    let fallback: [String]? = switch command {
    case .focus: ["workspace", String(position!)]
    case .move: ["move-node-to-workspace", String(position!)]
    case .next: ["workspace", "next", "--wrap-around"]
    case .prev: ["workspace", "prev", "--wrap-around"]
    default: nil
    }
    guard let fallback, let aerospace = AeroSpacePaths.locate() else { fail("AeroStage is not running") }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: aerospace)
    process.arguments = fallback
    do { try process.run() } catch { fail("cannot run aerospace: \(error)") }
    process.waitUntilExit()
    exit(process.terminationStatus)
} catch {
    fail("\(error)")
}
