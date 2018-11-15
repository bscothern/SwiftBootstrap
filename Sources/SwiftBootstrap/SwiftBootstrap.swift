import Foundation

//MARK: - Types
//MARK: Public

/// The errors that can result from `Bootstrap` operations.
public enum BootstrapError: Error {
    
    /// Raised when the `FileManager` fails to change directories
    case directoryChangeFailure
    
    /// The bootstrap executable cannot find `.build/` in it's file path.
    case invalidPath
    
    /// The bootstrap executable cannot find a directory it should change into.
    case directoryNotFound
    
    /// The command has failed to execute.
    case commandFailed(exitCode: Int32)
}

//MARK: - Properties
//MARK: Private

/// A convenient way to access the default file manager
private let fileManager = FileManager.default

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
    let process = Process()
    process.launchPath = "/usr/bin/env"
    process.arguments = command.lazy.split(separator: " ").map { String($0) }
    if quiet {
#if !os(Linux)
        // For some reason this is crashing on arm64 Linux...
        process.standardOutput = nil
        process.standardError = nil
#endif
    }
    process.launch()
    process.waitUntilExit()
    return process.terminationStatus
}

/// Moves the the `FileManager` for the executable to the root of the current source directory.
///
/// - Throws: A `BootstrapError` describing what has gone wrong.
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
///
/// - Throws: A `BootstrapError` describing what has gone wrong.
///
/// - Parameters:
///   - product: A product to build.
///     `default = ""`.
///   - quiet: When `false` the command will have its output printed to the console and when `true` the command is silent.
///     `default = false`.
public func swiftBuild(product: String = "", args: String = "", quiet: Bool = false) throws {
    let exitCode = shell("swift build \(product.isEmpty ? "":"--product \(product)") \(args.isEmpty ? "":args)", quiet: quiet)
    guard exitCode == 0 else {
        throw BootstrapError.commandFailed(exitCode: exitCode)
    }
}

/// Runs a `swift run Bootstrap-[project]` command inside the project checkout.
///
/// - Throws: A `BootstrapError` describing what has gone wrong.
///
/// - Parameters:
///   - project: The project found in `.build/checkouts` to build.
///   - quiet: When `false` the command will have its subcommands output printed to the console and when `true` the command is silent.
///     `default = false`.
public func bootstrap(project: String, quiet: Bool = false) throws {
    let originalDirectory = fileManager.currentDirectoryPath
    defer {
        fileManager.changeCurrentDirectoryPath(originalDirectory)
    }
    
    try moveToSourceRoot()
    do {
        try moveTo(project: project, inPath: ".build/checkouts")
    }
    catch {
        print("\(project) not found in .build/checkouts. Looking in root directory.")
        try moveTo(project: project, inPath: ".")
    }

    print("=== Bootstrapping \(project) ===")
    let exitCode = shell("swift run Bootstrap-\(project)", quiet: quiet)
    guard exitCode == 0 else {
        throw BootstrapError.commandFailed(exitCode: exitCode)
    }
    print("=== Finished Bootstrapping \(project) ===")
}

/// Recusivly initializes and updates git submodules.
///
/// - Throws: A `BootstrapError` describing what has gone wrong.
///
/// - Parameters:
///   - quiet: When `false` the command will have its output printed to the console and when `true` the command is silent.
///     `default = false`.
public func gitSubmodules(quiet: Bool = true) throws {
    let exitCode = shell("git submodule update --init --recursive", quiet: quiet)
    guard exitCode == 0 else {
        throw BootstrapError.commandFailed(exitCode: exitCode)
    }
}

/// Resolves Swift Package Manager dependencies.
///
/// - Throws: A `BootstrapError` describing what has gone wrong.
///
/// - Parameters:
///   - quiet: When `false` the command will have its output printed to the console and when `true` the command is silent.
///     `default = false`.
public func swiftPackageResolve(quiet: Bool = true) throws {
    let exitCode = shell("swift package resolve", quiet: quiet)
    guard exitCode == 0 else {
        throw BootstrapError.commandFailed(exitCode: exitCode)
    }
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

private func moveTo(project: String, inPath path: String) throws {
    let checkouts = try? fileManager.contentsOfDirectory(at: URL(string: path)!, includingPropertiesForKeys: nil)
    guard let projectDirectory = checkouts?.first(where: {
        $0.lastPathComponent.hasPrefix(project)
    })?.lastPathComponent
        else {
            throw BootstrapError.directoryNotFound
    }
    fileManager.changeCurrentDirectoryPath(path)
    fileManager.changeCurrentDirectoryPath(projectDirectory)
}
