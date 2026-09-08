// FixtureAgent.swift — synthetic offline ACP agent fixture (VOY-886 conformance).
//
// Compiled at test time with `xcrun swiftc -swift-version 6`. Uses only
// Foundation; it never imports the package under test so the golden wire
// behavior is independent of VoyagerSwiftACP code.
//
// Usage: FixtureAgent <scenario>
// Scenarios: normal | hold-prompt | malformed | stdout-eof | exit-17 | ignore-term

import Foundation

let scenario = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "normal"

func writeLine(_ string: String) {
    var data = Data(string.utf8)
    data.append(0x0A)
    FileHandle.standardOutput.write(data)
}

func response(id: Any, result: [String: Any]) throws -> String {
    var payload: [String: Any] = ["jsonrpc": "2.0", "id": id, "result": result]
    // JSONSerialization requires Bool ids to stay distinguishable; pass ids through as-is.
    payload["id"] = id
    let data = try JSONSerialization.data(withJSONObject: payload)
    return String(data: data, encoding: .utf8) ?? ""
}

func notification(method: String, params: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "method": method, "params": params])
    return String(data: data, encoding: .utf8) ?? ""
}

func sessionIdValue() -> String {
    "fixture-\(UUID().uuidString.prefix(8))"
}

if scenario == "ignore-term" {
    signal(SIGTERM, SIG_IGN)
}

if scenario == "malformed" {
    // Read the initialize request, answer, then poison the wire.
    _ = FileHandle.standardInput.availableData
    try writeLine(response(id: 1, result: ["protocolVersion": 1, "agentCapabilities": [:]]))
    writeLine("DEFINITELY NOT JSON @@")
    exit(0)
}

if scenario == "stdout-eof" {
    _ = FileHandle.standardInput.availableData
    try writeLine(response(id: 1, result: ["protocolVersion": 1, "agentCapabilities": [:]]))
    fflush(stdout)
    // Close stdout while staying alive: client must observe EOF, not exit.
    close(1)
    sleep(30)
    exit(0)
}

if scenario == "exit-17" {
    _ = FileHandle.standardInput.availableData
    try writeLine(response(id: 1, result: ["protocolVersion": 1, "agentCapabilities": [:]]))
    fflush(stdout)
    exit(17)
}

var pendingPromptID: Any?
var pendingPromptCancelled = false
var sessionCounter = 0
var updateCounter = 0

while true {
    let data = FileHandle.standardInput.availableData
    if data.isEmpty {
        break
    }
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let method = object["method"] as? String
    else {
        continue
    }
    let id = object["id"] as Any
    let params = object["params"] as? [String: Any] ?? [:]

    switch method {
    case "initialize":
        try writeLine(response(id: id, result: ["protocolVersion": 1, "agentCapabilities": [:]]))
    case "session/new":
        sessionCounter += 1
        try writeLine(response(id: id, result: ["sessionId": sessionIdValue()]))
    case "session/prompt":
        if scenario == "hold-prompt" {
            pendingPromptID = id
            pendingPromptCancelled = false
            // Wait for the cancel notification before answering.
            var answered = false
            while !answered {
                let wait = FileHandle.standardInput.availableData
                if wait.isEmpty {
                    answered = true
                    break
                }
                if let waitObject = try? JSONSerialization.jsonObject(with: wait) as? [String: Any],
                   let waitMethod = waitObject["method"] as? String,
                   waitMethod == "session/cancel"
                {
                    pendingPromptCancelled = true
                    answered = true
                    try writeLine(response(id: id, result: ["stopReason": "cancelled"]))
                }
            }
        } else {
            let sessionID = params["sessionId"] as? String ?? "s"
            for _ in 0 ..< 2 {
                updateCounter += 1
                try writeLine(notification(method: "session/update", params: [
                    "sessionId": sessionID,
                    "update": [
                        "sessionUpdate": "agent_message_chunk",
                        "content": ["type": "text", "text": "update \(updateCounter)"],
                    ],
                ]))
            }
            try writeLine(response(id: id, result: ["stopReason": "end_turn"]))
        }
    default:
        break
    }
}

if scenario == "ignore-term" {
    // SIGTERM is trapped as a no-op: the harness must escalate to SIGKILL.
    sleep(30)
}

exit(0)
