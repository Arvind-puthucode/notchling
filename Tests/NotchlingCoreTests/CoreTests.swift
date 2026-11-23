import XCTest
@testable import NotchlingCore

final class TaskParserTests: XCTestCase {
    let cal = Calendar.current

    func testRelativeDayWithTime() throws {
        let now = Date()
        let r = try XCTUnwrap(TaskParser.parse("call mom tomorrow at 5pm", now: now))
        XCTAssertEqual(r.title, "call mom")
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        XCTAssertEqual(r.day, tomorrow)
        let due = try XCTUnwrap(r.due)
        XCTAssertEqual(cal.component(.hour, from: due), 17)
        XCTAssertEqual(cal.startOfDay(for: due), tomorrow)
    }

    func testDayWithoutTimeHasNoReminder() throws {
        let r = try XCTUnwrap(TaskParser.parse("buy milk tomorrow"))
        XCTAssertEqual(r.title, "buy milk")
        XCTAssertNotNil(r.day)
        XCTAssertNil(r.due)
    }

    func testPlainTitle() throws {
        let r = try XCTUnwrap(TaskParser.parse("  write report  "))
        XCTAssertEqual(r.title, "write report")
        XCTAssertNil(r.day)
        XCTAssertFalse(r.important)
    }

    func testImportantAndLink() throws {
        let r = try XCTUnwrap(TaskParser.parse("review https://example.com/pr/1 !"))
        XCTAssertEqual(r.title, "review")
        XCTAssertTrue(r.important)
        XCTAssertEqual(r.links, ["https://example.com/pr/1"])
    }

    func testEmpty() {
        XCTAssertNil(TaskParser.parse("   "))
    }
}

final class PlannerOpsTests: XCTestCase {
    let cal = Calendar.current

    func testCarryForwardMovesOpenPastTasksAndDropsTime() {
        let now = Date()
        let today = cal.startOfDay(for: now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        var d = PlannerData()
        d.tasks = [
            TaskItem(title: "open", day: yesterday, due: yesterday.addingTimeInterval(3600)),
            TaskItem(title: "done", day: yesterday, completedAt: yesterday),
            TaskItem(title: "inbox"),
        ]
        d.carryForward(now: now)
        XCTAssertEqual(d.tasks[0].day, today)
        XCTAssertNil(d.tasks[0].due)
        XCTAssertEqual(d.tasks[1].day, yesterday)
        XCTAssertNil(d.tasks[2].day)
    }

    func testMoveKeepsTimeOfDay() {
        let today = cal.startOfDay(for: Date())
        let due = cal.date(bySettingHour: 14, minute: 30, second: 0, of: today)!
        var d = PlannerData()
        d.tasks = [TaskItem(title: "t", day: today, due: due, reminded: true)]
        let target = cal.date(byAdding: .day, value: 3, to: today)!
        d.move(d.tasks[0].id, to: target)
        XCTAssertEqual(d.tasks[0].day, target)
        XCTAssertEqual(d.tasks[0].due, cal.date(bySettingHour: 14, minute: 30, second: 0, of: target))
        XCTAssertFalse(d.tasks[0].reminded)
        d.move(d.tasks[0].id, to: nil)
        XCTAssertNil(d.tasks[0].day)
        XCTAssertNil(d.tasks[0].due)
    }

    func testDueReminders() {
        let now = Date()
        var d = PlannerData()
        d.tasks = [
            TaskItem(title: "past", due: now.addingTimeInterval(-60)),
            TaskItem(title: "future", due: now.addingTimeInterval(600)),
            TaskItem(title: "fired", due: now.addingTimeInterval(-60), reminded: true),
        ]
        XCTAssertEqual(d.dueReminders(now: now).map(\.title), ["past"])
    }

    func testNotesRoundTrip() {
        var d = PlannerData()
        let day = Date()
        d.setNote("hello", for: day)
        XCTAssertEqual(d.note(for: day), "hello")
        d.setNote("", for: day)
        XCTAssertTrue(d.notes.isEmpty)
    }

    func testDataFileRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("d.json")
        let file = DataFile(url: url)
        XCTAssertEqual(try file.load(), PlannerData())
        try file.update { $0.addTask(parsing: "x") }
        XCTAssertEqual(try file.load().tasks.map(\.title), ["x"])
    }
}

final class FocusClockTests: XCTestCase {
    func testCountdownPauseResumeAndAddFive() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var c = FocusClock()
        c.start(.countdown, minutes: 25, at: t0)
        XCTAssertEqual(c.display(at: t0.addingTimeInterval(60)), 24 * 60)
        c.pause(at: t0.addingTimeInterval(60))
        // Ten minutes asleep / paused do not count.
        c.resume(at: t0.addingTimeInterval(660))
        XCTAssertEqual(c.display(at: t0.addingTimeInterval(720)), 23 * 60)
        c.addFiveMinutes()
        XCTAssertEqual(c.display(at: t0.addingTimeInterval(720)), 28 * 60)
        let s = c.stop(at: t0.addingTimeInterval(720))
        XCTAssertEqual(s?.activeSeconds, 120)
        XCTAssertFalse(c.isActive)
    }

    func testCountdownFinishesAndCaps() {
        let t0 = Date(timeIntervalSince1970: 0)
        var c = FocusClock()
        c.start(.countdown, minutes: 1, at: t0)
        XCTAssertTrue(c.isFinished(at: t0.addingTimeInterval(61)))
        XCTAssertEqual(c.stop(at: t0.addingTimeInterval(300))?.activeSeconds, 60)
    }

    func testShortSessionsAreNotLogged() {
        var c = FocusClock()
        c.start(.stopwatch, at: Date(timeIntervalSince1970: 0))
        XCTAssertNil(c.stop(at: Date(timeIntervalSince1970: 30)))
    }
}

final class DayPlannerTests: XCTestCase {
    func testFitsAroundBusyBlocksImportantFirst() {
        let base = Date(timeIntervalSinceReferenceDate: 0) // aligned to 15 min
        let a = TaskItem(title: "a", createdAt: base)
        let b = TaskItem(title: "b", important: true, createdAt: base.addingTimeInterval(1))
        let busy = [DayPlanner.Busy(start: base.addingTimeInterval(1800), end: base.addingTimeInterval(3600))]
        let plan = DayPlanner.plan(tasks: [a, b], busy: busy, now: base.addingTimeInterval(60), dayEnd: base.addingTimeInterval(4 * 3600))
        // now rounds to +15m; [15m,45m) collides with busy 30-60m -> b at 60m, a at 90m.
        XCTAssertEqual(plan.map(\.0), [b.id, a.id])
        XCTAssertEqual(plan.map(\.1), [base.addingTimeInterval(3600), base.addingTimeInterval(5400)])
    }

    func testDropsTasksPastDayEnd() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let tasks = (0..<5).map { TaskItem(title: "\($0)") }
        let plan = DayPlanner.plan(tasks: tasks, busy: [], now: base, dayEnd: base.addingTimeInterval(3600))
        XCTAssertEqual(plan.count, 2)
    }
}

final class InsightsTests: XCTestCase {
    func testStreakAndBestHour() {
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        var d = PlannerData()
        for back in 0..<3 {
            let day = cal.date(byAdding: .day, value: -back, to: today)!
            d.tasks.append(TaskItem(title: "t", completedAt: day.addingTimeInterval(3600)))
        }
        d.sessions = [FocusSession(start: cal.date(bySettingHour: 10, minute: 0, second: 0, of: today)!, activeSeconds: 1500)]
        let i = Insights.compute(d, now: now)
        XCTAssertEqual(i.streak, 3)
        XCTAssertEqual(i.bestFocusHour, 10)
        XCTAssertEqual(i.completedThisWeek, 3)
    }
}

final class MeetingLinkTests: XCTestCase {
    func testFindsKnownHostsOnly() {
        XCTAssertNil(MeetingLink.find(in: ["see https://example.com/doc", nil]))
        XCTAssertEqual(
            MeetingLink.find(in: [nil, "Room 4", "Join: https://us02web.zoom.us/j/123?pwd=x"])?.host,
            "us02web.zoom.us")
        XCTAssertEqual(MeetingLink.find(in: ["https://meet.google.com/abc-defg-hij"])?.host, "meet.google.com")
    }
}

final class ReminderSyncTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testCreatesUnlinkedOpenTasksAndImportsUnknownReminders() {
        var d = PlannerData()
        d.tasks = [TaskItem(title: "local", createdAt: t0), TaskItem(title: "done", completedAt: t0, createdAt: t0)]
        let r = RemoteReminder(id: "R1", title: "from phone", day: nil, due: nil, completedAt: nil, modified: t0)
        let ops = ReminderSync.reconcile(&d, remote: [r])
        XCTAssertEqual(ops.create.map(\.title), ["local"])
        XCTAssertEqual(d.tasks.map(\.title), ["local", "done", "from phone"])
        XCTAssertEqual(d.tasks.last?.reminderID, "R1")
    }

    func testNewerSideWins() {
        var d = PlannerData()
        d.tasks = [
            TaskItem(title: "old local", createdAt: t0, modifiedAt: t0, reminderID: "A"),
            TaskItem(title: "new local", createdAt: t0, modifiedAt: t0.addingTimeInterval(100), reminderID: "B"),
        ]
        let remote = [
            RemoteReminder(id: "A", title: "edited on phone", day: nil, due: nil, completedAt: t0.addingTimeInterval(50), modified: t0.addingTimeInterval(50)),
            RemoteReminder(id: "B", title: "stale", day: nil, due: nil, completedAt: nil, modified: t0),
        ]
        let ops = ReminderSync.reconcile(&d, remote: remote)
        XCTAssertEqual(d.tasks[0].title, "edited on phone")
        XCTAssertTrue(d.tasks[0].isDone)
        XCTAssertEqual(ops.update.map(\.0), ["B"])
        XCTAssertEqual(d.tasks[1].title, "new local")
    }

    func testDeletesBothWays() {
        var d = PlannerData()
        d.tasks = [TaskItem(title: "gone remotely", createdAt: t0, reminderID: "X"), TaskItem(title: "kill", createdAt: t0, reminderID: "Y")]
        d.delete(d.tasks[1].id)
        let ops = ReminderSync.reconcile(&d, remote: [RemoteReminder(id: "Y", title: "kill", day: nil, due: nil, completedAt: nil, modified: t0)])
        XCTAssertTrue(d.tasks.isEmpty)
        XCTAssertEqual(ops.delete, ["Y"])
        XCTAssertNil(d.deletedReminderIDs)
    }

    func testEqualContentDoesNotPush() {
        var d = PlannerData()
        d.tasks = [TaskItem(title: "same", createdAt: t0, modifiedAt: t0.addingTimeInterval(60), reminderID: "S")]
        let ops = ReminderSync.reconcile(&d, remote: [RemoteReminder(id: "S", title: "same", day: nil, due: nil, completedAt: nil, modified: t0)])
        XCTAssertTrue(ops.update.isEmpty)
    }
}

final class ICSTests: XCTestCase {
    func testParsesUTCFoldedAndWeeklyRecurrenceWithExdate() throws {
        let ics = """
        BEGIN:VCALENDAR\r
        BEGIN:VEVENT\r
        UID:one\r
        SUMMARY:Standup with a very long\r
          title\r
        DTSTART:20261123T040000Z\r
        DTEND:20261123T041500Z\r
        RRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=4\r
        EXDATE:20261125T040000Z\r
        LOCATION:https://meet.google.com/abc-defg-hij\r
        BEGIN:VALARM\r
        TRIGGER:-PT10M\r
        END:VALARM\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        UID:two\r
        SUMMARY:Holiday\r
        DTSTART;VALUE=DATE:20261126\r
        END:VEVENT\r
        END:VCALENDAR\r
        """
        let from = Date(timeIntervalSince1970: 1_795_000_000) // 2026-11-18
        let to = from.addingTimeInterval(30 * 86400)
        let events = ICS.events(in: ics, from: from, to: to)
        let standups = events.filter { $0.uid == "one" }
        XCTAssertEqual(standups.first?.title, "Standup with a very long title")
        // COUNT=4 -> Mon 23, Wed 25 (excluded), Mon 30, Wed 2 Dec.
        XCTAssertEqual(standups.count, 3)
        XCTAssertEqual(standups.first?.start, ISO8601DateFormatter().date(from: "2026-11-23T04:00:00Z"))
        XCTAssertEqual(standups.first.map { $0.end.timeIntervalSince($0.start) }, 900)
        let holiday = try XCTUnwrap(events.first { $0.uid == "two" })
        XCTAssertTrue(holiday.isAllDay)
        XCTAssertEqual(holiday.end.timeIntervalSince(holiday.start), 86400)
    }

    func testTZIDAndDuration() throws {
        let ics = "BEGIN:VEVENT\nUID:x\nDTSTART;TZID=Asia/Kolkata:20261201T100000\nDURATION:PT1H30M\nSUMMARY:Call\\, sync\nEND:VEVENT"
        let e = try XCTUnwrap(ICS.events(in: ics, from: .distantPast, to: .distantFuture).first)
        XCTAssertEqual(e.start, ISO8601DateFormatter().date(from: "2026-12-01T04:30:00Z"))
        XCTAssertEqual(e.end.timeIntervalSince(e.start), 5400)
        XCTAssertEqual(e.title, "Call, sync")
    }
}

final class SortTests: XCTestCase {
    func testDoneLastAndByTitle() {
        let a = TaskItem(title: "b"), b = TaskItem(title: "a"), c = TaskItem(title: "0", completedAt: Date())
        XCTAssertEqual(TaskSort.title.sorted([c, a, b]).map(\.title), ["a", "b", "0"])
    }
}
