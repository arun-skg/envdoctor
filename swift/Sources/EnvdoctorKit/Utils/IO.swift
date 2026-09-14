import Foundation

extension FileHandle {
    /// Write a UTF-8 string, matching `process.stderr.write(...)` in the
    /// reference CLI.
    func write(_ string: String) {
        write(Data(string.utf8))
    }
}
