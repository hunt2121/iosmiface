// SPDX-License-Identifier: MIT
// Консольний інтерфейс як у WatchfaceCompiler.exe:
//   wfc <unpack|build> <device> <input> <output> [--uidmap FILE] [--quirks]
// --quirks — відтворювати помилки exe (для побайтової звірки з еталоном).

import Foundation
import FaceCompiler

let logger = FaceCompilerLog()
logger.onLine = { level, s in print("[\(level.rawValue)] \(s)") }
print("[info] WatchfaceCompiler version \(WatchfaceCompiler.version) (Swift port)")

var args = Array(CommandLine.arguments.dropFirst())
var uidmap: String?
var quirks = false
if let i = args.firstIndex(of: "--uidmap"), i + 1 < args.count { uidmap = args[i + 1]; args.removeSubrange(i...(i + 1)) }
if let i = args.firstIndex(of: "--quirks") { quirks = true; args.remove(at: i) }
guard args.count == 4 else {
    print("Usage: wfc <unpack|build> <device> <input> <output> [--uidmap FILE] [--quirks]")
    exit(1)
}
let (mode, device, input, output) = (args[0], args[1], args[2], args[3])
let options = FaceCompilerOptions(exeQuirks: quirks)
WatchfaceCompiler.checkDevice(device, log: logger)

do {
    switch mode {
    case "unpack":
        guard let data = FileManager.default.contents(atPath: input) else { throw FaceCompilerError("Can't open \(input)") }
        let u = try WatchfaceCompiler.unpack(data, to: DirectoryStorage(URL(fileURLWithPath: output)), options: options, log: logger)
        if let uidmap { try Data(u.uidMap()).write(to: URL(fileURLWithPath: uidmap)) }
    case "build":
        let b = FaceBuilder(storage: DirectoryStorage(URL(fileURLWithPath: input)), options: options, log: logger)
        let data = try b.build()
        try data.write(to: URL(fileURLWithPath: output))
        print("[info] Saved to \(output)")
        if let uidmap { try Data(b.uidMap()).write(to: URL(fileURLWithPath: uidmap)) }
    default:
        throw FaceCompilerError("Unknown mode: \(mode). Possible modes: unpack, build")
    }
} catch {
    print("[critical] Critical error: \(error)")
    exit(2)
}
