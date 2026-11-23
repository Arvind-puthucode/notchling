import Foundation
import NotchlingCore

// Minimal MCP server over stdio (newline-delimited JSON-RPC 2.0).
// Reads and writes the same data file as the app; the app picks up changes live.

let file = DataFile.standard
let iso: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.timeZone = .current // agents see the user's wall-clock time
    return f
}()
setvbuf(stdout, nil, _IOLBF, 0)

func send(_ obj: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: data, encoding: .utf8) else { return }
    print(s)
}

func text(_ s: String, isError: Bool = false) -> [String: Any] {
    ["content": [["type": "text", "text": s]], "isError": isError]
}

func describe(_ t: TaskItem) -> [String: Any] {
    var o: [String: Any] = ["id": t.id.uuidString, "title": t.title, "done": t.isDone, "important": t.important]
    if let d = t.day { o["day"] = DayKey.key(d) }
    if let d = t.due { o["due"] = iso.string(from: d) }
    if !t.links.isEmpty { o["links"] = t.links }
    return o
}

func json(_ v: Any) -> String {
    (try? JSONSerialization.data(withJSONObject: v, options: [.prettyPrinted, .sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
}

func prop(_ type: String, _ desc: String) -> [String: Any] { ["type": type, "description": desc] }

let tools: [[String: Any]] = [
    ["name": "list_tasks", "description": "List tasks. scope: today (default), inbox, week, all.",
     "inputSchema": ["type": "object", "properties": ["scope": prop("string", "today | inbox | week | all")]]],
    ["name": "add_task", "description": "Add a task. Natural language dates work, e.g. 'call mom tomorrow at 5pm'. '!' marks important. Undated tasks go to today unless inbox=true.",
     "inputSchema": ["type": "object", "properties": ["text": prop("string", "Task text"), "inbox": prop("boolean", "Put undated task in Inbox")], "required": ["text"]]],
    ["name": "complete_task", "description": "Mark a task done by id.",
     "inputSchema": ["type": "object", "properties": ["id": prop("string", "Task id")], "required": ["id"]]],
    ["name": "get_note", "description": "Read today's note (or a yyyy-MM-dd day).",
     "inputSchema": ["type": "object", "properties": ["day": prop("string", "yyyy-MM-dd, default today")]]],
    ["name": "append_note", "description": "Append a line to today's note.",
     "inputSchema": ["type": "object", "properties": ["text": prop("string", "Line to append")], "required": ["text"]]],
    ["name": "insights", "description": "Completed tasks, focus minutes, streak and best focus hour.",
     "inputSchema": ["type": "object", "properties": [:] as [String: Any]]],
]

func call(_ name: String, _ args: [String: Any]) throws -> [String: Any] {
    let cal = Calendar.current
    let now = Date()
    switch name {
    case "list_tasks":
        let data = try file.load()
        let scope = args["scope"] as? String ?? "today"
        let list: [TaskItem]
        switch scope {
        case "inbox": list = data.inbox
        case "all": list = data.tasks.sorted(by: PlannerData.order)
        case "week":
            list = (0..<7).flatMap { data.tasks(on: cal.date(byAdding: .day, value: $0, to: now)!) }
        default: list = data.tasks(on: now)
        }
        return text(json(list.map(describe)))
    case "add_task":
        guard let t = args["text"] as? String else { return text("text is required", isError: true) }
        let inbox = args["inbox"] as? Bool ?? false
        let task = try file.update { $0.addTask(parsing: t, defaultDay: inbox ? nil : now) }
        guard let task else { return text("empty task", isError: true) }
        return text(json(describe(task)))
    case "complete_task":
        guard let s = args["id"] as? String, let id = UUID(uuidString: s) else { return text("valid id is required", isError: true) }
        let ok = try file.update { $0.setDone(id) }
        return ok ? text("done") : text("no task with id \(s)", isError: true)
    case "get_note":
        let data = try file.load()
        if let key = args["day"] as? String { return text(data.notes[key] ?? "") }
        return text(data.note(for: now))
    case "append_note":
        guard let line = args["text"] as? String else { return text("text is required", isError: true) }
        try file.update { d in
            let current = d.note(for: now)
            d.setNote(current.isEmpty ? line : current + "\n" + line, for: now)
        }
        return text("ok")
    case "insights":
        let i = Insights.compute(try file.load())
        return text(json([
            "completedToday": i.completedToday, "completedThisWeek": i.completedThisWeek,
            "focusMinutesToday": i.focusMinutesToday, "focusMinutesThisWeek": i.focusMinutesThisWeek,
            "streak": i.streak, "bestFocusHour": i.bestFocusHour as Any,
        ]))
    default:
        return text("unknown tool \(name)", isError: true)
    }
}

while let line = readLine() {
    guard let data = line.data(using: .utf8),
          let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let method = msg["method"] as? String else { continue }
    let id = msg["id"]
    // Notifications carry no id and get no reply.
    guard let id else { continue }
    let params = msg["params"] as? [String: Any] ?? [:]
    switch method {
    case "initialize":
        send(["jsonrpc": "2.0", "id": id, "result": [
            "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
            "capabilities": ["tools": [:] as [String: Any]],
            "serverInfo": ["name": "notchling", "version": "0.1.0"],
        ]])
    case "ping":
        send(["jsonrpc": "2.0", "id": id, "result": [:] as [String: Any]])
    case "tools/list":
        send(["jsonrpc": "2.0", "id": id, "result": ["tools": tools]])
    case "tools/call":
        let name = params["name"] as? String ?? ""
        let args = params["arguments"] as? [String: Any] ?? [:]
        do {
            send(["jsonrpc": "2.0", "id": id, "result": try call(name, args)])
        } catch {
            send(["jsonrpc": "2.0", "id": id, "result": text("error: \(error.localizedDescription)", isError: true)])
        }
    default:
        send(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "method not found: \(method)"]])
    }
}
