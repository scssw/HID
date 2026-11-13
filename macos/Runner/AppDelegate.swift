import Cocoa
import FlutterMacOS
import UserNotifications

@main
class AppDelegate: FlutterAppDelegate {
  static func main() {
    let arguments = CommandLine.arguments
    if arguments.count >= 2 {
      switch arguments[1] {
      case "--tunnel", "tunnel":
        let subArgs = Array(arguments.dropFirst(2))
        exit(runCoreCommand(["tunnel"] + subArgs))
      default:
        break
      }
    }
    exit(NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv))
  }

  private static func runCoreCommand(_ command: [String]) -> Int32 {
    let frameworkPaths = [
      Bundle.main.privateFrameworksURL?.appendingPathComponent("libcore.dylib").path,
      Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/libcore.dylib").path,
      Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/libcore.dylib").path,
    ]
    var library: UnsafeMutableRawPointer?
    for p in frameworkPaths {
      if let p = p, FileManager.default.fileExists(atPath: p) {
        library = dlopen(p, RTLD_NOW)
        if library != nil { break }
      }
    }
    guard let lib = library, let symbol = dlsym(lib, "parseCli") else {
      fputs("libcore is missing from the app bundle\n", stderr)
      return 1
    }
    typealias ParseCli = @convention(c) (Int32, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> UnsafeMutablePointer<CChar>?
    let parseCli = unsafeBitCast(symbol, to: ParseCli.self)
    var argv = ([CommandLine.arguments[0]] + command).map { strdup($0) } + [nil]
    let error = argv.withUnsafeMutableBufferPointer { parseCli(Int32(command.count + 1), $0.baseAddress!) }
    argv.forEach { free($0) }
    guard let error = error else { return 0 }
    defer { free(error) }
    let message = String(cString: error)
    guard message.isEmpty else {
      fputs(message + "\n", stderr)
      return 1
    }
    return 0
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationDidFinishLaunching(_ aNotification: Notification) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge]) { granted, error in
      if let error = error {
        print("Error requesting notification authorization: \(error)")
      }
    }
    super.applicationDidFinishLaunching(aNotification)
  }
}
