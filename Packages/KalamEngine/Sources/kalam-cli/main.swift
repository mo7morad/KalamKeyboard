// kalam-cli: debug and evaluation tool for KalamEngine. One file per subcommand, registered here.
import Foundation

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

let commands: [String: ([String]) -> Int32] = ["suggest": suggest, "verify": verify]
let arguments = Array(CommandLine.arguments.dropFirst())
guard let name = arguments.first, let command = commands[name] else {
    print("usage: kalam-cli <\(commands.keys.sorted().joined(separator: "|"))> ...")
    exit(2)
}
exit(command(Array(arguments.dropFirst())))
