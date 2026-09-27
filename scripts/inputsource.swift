// inputsource            -> prints current keyboard input source ID
// inputsource <id>       -> selects that input source (e.g. com.apple.keylayout.US)
import Carbon
let args = CommandLine.arguments
if args.count < 2 {
    let cur = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    let id = Unmanaged<CFString>.fromOpaque(TISGetInputSourceProperty(cur, kTISPropertyInputSourceID)).takeUnretainedValue()
    print(id)
} else {
    let filter = [kTISPropertyInputSourceID as String: args[1]] as CFDictionary
    guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
          let src = list.first else { FileHandle.standardError.write("not found: \(args[1])\n".data(using: .utf8)!); exit(1) }
    exit(TISSelectInputSource(src) == noErr ? 0 : 1)
}
