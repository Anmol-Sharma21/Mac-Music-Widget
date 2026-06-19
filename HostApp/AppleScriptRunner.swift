//  AppleScriptRunner.swift
//  Executes AppleScript in-process via NSAppleScript. Running in-process (rather
//  than shelling out to /usr/bin/osascript) is important: the Apple Events are
//  attributed to *this* app, so the macOS Automation (TCC) permission prompt and
//  grant apply to MusicGlass itself — required for a sandboxed app.
//
//  IMPORTANT: NSAppleScript must NOT run on the main thread here. A first-time
//  Apple Event blocks until the user answers the Automation (TCC) prompt; on the
//  main thread that freezes the whole app (UI + timer) and drops the widget's
//  XPC connections. The engine therefore calls these from a dedicated serial
//  background queue. NSAppleScript pumps its own CFRunLoop for the AE reply on
//  whatever thread it runs on, so background execution is fine; the engine's
//  serial queue guarantees no concurrent NSAppleScript use.

import Foundation

enum AppleScriptRunner {

    enum ScriptError: Error, CustomStringConvertible {
        case compileFailed(String)
        case executionFailed(code: Int, message: String)

        var description: String {
            switch self {
            case .compileFailed(let m):            return "compile failed: \(m)"
            case .executionFailed(let code, let m): return "exec failed (\(code)): \(m)"
            }
        }
    }

    /// Compile + run a script source, returning its string result.
    /// Throws `ScriptError`; an Automation-permission denial surfaces as
    /// `errAEEventNotPermitted` (-1743) or `errAEEventWouldRequireUserConsent`.
    @discardableResult
    static func run(_ source: String) throws -> String {
        guard let script = NSAppleScript(source: source) else {
            throw ScriptError.compileFailed("could not construct NSAppleScript")
        }

        var compileError: NSDictionary?
        guard script.compileAndReturnError(&compileError) else {
            throw ScriptError.compileFailed(Self.message(from: compileError))
        }

        var execError: NSDictionary?
        let descriptor = script.executeAndReturnError(&execError)
        if let execError {
            let code = (execError[NSAppleScript.errorNumber] as? Int) ?? -1
            throw ScriptError.executionFailed(code: code, message: Self.message(from: execError))
        }
        return descriptor.stringValue ?? ""
    }

    /// Run a script, returning nil on any error (for best-effort polling where a
    /// not-running app or a momentary AE failure shouldn't be treated as fatal).
    static func runOrNil(_ source: String) -> String? {
        try? run(source)
    }

    /// Run a script whose result is raw binary (e.g. artwork `raw data`), and
    /// return the descriptor's bytes. Returns nil for `missing value`/errors.
    static func runForData(_ source: String) -> Data? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var compileError: NSDictionary?
        guard script.compileAndReturnError(&compileError) else { return nil }
        var execError: NSDictionary?
        let descriptor = script.executeAndReturnError(&execError)
        guard execError == nil else { return nil }
        // `missing value` / null descriptors carry no usable data.
        let data = descriptor.data
        return data.isEmpty ? nil : data
    }

    /// True if the error is specifically a denied/!-yet-granted Automation prompt.
    static func isPermissionError(_ error: Error) -> Bool {
        guard case let ScriptError.executionFailed(code, _) = error else { return false }
        // -1743: errAEEventNotPermitted, -1744: would require user consent.
        return code == -1743 || code == -1744
    }

    private static func message(from dict: NSDictionary?) -> String {
        (dict?[NSAppleScript.errorMessage] as? String) ?? "unknown error"
    }
}
