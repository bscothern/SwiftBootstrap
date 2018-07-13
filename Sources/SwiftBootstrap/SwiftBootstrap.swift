import Foundation

#if os(macOS)
private typealias Runner = Process
#elseif os(Linux)
private typealias Runner = Task
#endif

//MARK: - Types
//MARK: Public

/// The errors that can result from `Bootstrap` operations.
public enum BootstrapError: Error {
    
    /// Raised when the `FileManager` fails to change directories
    case directoryChangeFailure
    
    /// The executable cannot find `.build/` in the path to it.
    case invalidPath
}

//MARK: - Properties
//MARK: Private

/// A convenient way to access the default file manager
private static let fileManager = FileManager.default

//MARK: - Funcs
//MARK: Public

/// Runs a shell command.
///
/// - Parameters:
///   - command: The command and arguments that should be executed.
///   - quiet: When `true` (the default) standared out and standard error are set to `nil`.
///         When `false` the default standard out and standard error are used.
/// - Returns: The termination status of the shell command
public func shell(_ command: String, quiet: Bool = true) -> Int32 {
    let task = Runner()
    task.launchPath = "/usr/bin/env"
    task.arguments = command.lazy.split(separator: " ").map { String($0) }
    if quiet {
        task.standardOutput = nil
        task.standardError = nil
    }
    task.launch()
    task.waitUntilExit()
    return task.terminationStatus
}

/// Moves the the `FileManager` for the executable to the root of the current source directory.
///
/// - Throws: A `Bootstrap.Error` describing what has gone wrong while modifying the `FileManager`.
public func moveToSourceRoot() throws {
    let pathToThisApp = CommandLine.arguments.first!
    let directoryOfThisApp = String(pathToThisApp.lazy.reversed().split(separator: "/", maxSplits: 1).last!.reversed())
    
    let components = directoryOfThisApp.components(separatedBy: ".build/")
    guard components.count > 1 else {
        throw BootstrapError.invalidPath
    }
    
    guard fileManager.changeCurrentDirectoryPath(directoryOfThisApp) else {
        throw BootstrapError.directoryChangeFailure
    }
    
    let pathFromBuild = components.last!
    let popsToRootDirectory = pathFromBuild.split(separator: "/").count + 1 // Adding 1 to get out of .build/
    guard fileManager.changeCurrentDirectoryPath(directoryPopPath(count: popsToRootDirectory)) else {
        throw BootstrapError.directoryChangeFailure
    }
}

/// Run a default `swift build` command.
public func swiftBuild() {
    _ = shell("swift build", quiet: false)
}

//MARK: Private

/// Moves up a number of directories.
///
/// - Parameter count: The number of directories that should be moved up.
/// - Returns: A `String` that is the relative path `count` directories above the current location.
private func directoryPopPath(count: Int) -> String {
    var toReturn = ""
    for _ in 0 ..< count {
        if !toReturn.isEmpty {
            toReturn += "/"
        }
        toReturn += ".."
    }
    return toReturn
}

