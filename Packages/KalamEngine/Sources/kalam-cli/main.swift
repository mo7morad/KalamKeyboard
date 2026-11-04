// kalam-cli: debug and evaluation tool for KalamEngine. One file per subcommand, registered here.
import Foundation
import KalamEngine

/// `--name value` pairs; a repeated flag keeps every value. Other arguments are ignored.
func parseFlags(_ args: [String]) -> [String: [String]] {
    var flags: [String: [String]] = [:]
    var i = 0
    while i < args.count {
        if args[i].hasPrefix("--"), i + 1 < args.count {
            flags[String(args[i].dropFirst(2)), default: []].append(args[i + 1])
            i += 2
        } else {
            i += 1
        }
    }
    return flags
}

/// EngineConfig with every `--set name=value` applied; nil (after printing why) on a bad one.
func parseConfig(_ flags: [String: [String]]) -> EngineConfig? {
    var config = EngineConfig()
    for setting in flags["set"] ?? [] {
        let parts = setting.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2, config.set(parts[0], parts[1]) else {
            print("bad --set \(setting); names: \(EngineConfig.names.joined(separator: ", "))")
            return nil
        }
    }
    return config
}

let commands: [String: ([String]) -> Int32] = ["suggest": suggest, "verify": verify, "eval-personal": evalPersonal, "eval": eval, "tapmap": tapmap]
let arguments = Array(CommandLine.arguments.dropFirst())
guard let name = arguments.first, let command = commands[name] else {
    print("usage: kalam-cli <\(commands.keys.sorted().joined(separator: "|"))> ...")
    exit(2)
}
exit(command(Array(arguments.dropFirst())))
