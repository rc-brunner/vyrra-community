import CoreMedia
import Foundation
import ScreenCaptureKit

// Capture audio from the chosen calling application. No screen output is registered.
private final class MeetingAudio: NSObject, SCStreamOutput, SCStreamDelegate {
    let lock = NSLock()
    var stream: SCStream?
    var failed = false
    var pcm: [Float] = []
    var phase = 0.0
    var sum = 0.0
    var count = 0

    func start(_ bundle: String) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        guard let app = content.applications.first(where: { $0.bundleIdentifier == bundle }), let display = content.displays.first else { throw CocoaError(.fileNoSuchFile) }
        let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = 2; config.height = 2; config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.capturesAudio = true; config.excludesCurrentProcessAudio = true; config.sampleRate = 48_000; config.channelCount = 1
        let capture = SCStream(filter: filter, configuration: config, delegate: self)
        try capture.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.vyrra.meeting.audio"))
        try await capture.startCapture()
        stream = capture
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { lock.lock(); failed = true; lock.unlock() }
    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sample.isValid, let description = sample.formatDescription,
              let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else { return }
        lock.lock(); defer { lock.unlock() }
        guard !failed else { return }
        guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32, format.mChannelsPerFrame == 1, format.mSampleRate >= 16000,
              let block = sample.dataBuffer, pcm.count <= 16_000 * 120 else { failed = true; return }
        let n = sample.numSamples
        var frames = [Float](repeating: 0, count: n)
        let result = frames.withUnsafeMutableBytes { bytes in
            guard let address = bytes.baseAddress else { return noErr }
            return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes.count, destination: address)
        }
        guard result == noErr else { failed = true; return }
        for value in frames {
            sum += Double(value); count += 1; phase += 16_000
            if phase >= format.mSampleRate { pcm.append(Float(sum / Double(count))); sum = 0; count = 0; phase -= format.mSampleRate }
        }
    }
}
@_cdecl("vyrra_meeting_audio_open")
public func openAudio(_ bundle: UnsafePointer<CChar>) -> UnsafeMutableRawPointer? {
    let id = String(cString: bundle), result = DispatchSemaphore(value: 0), audio = MeetingAudio()
    Task { do { try await audio.start(id) } catch { audio.failed = true }; result.signal() }
    // The permission dialog belongs to the app. Keep this wait off the UI thread.
    result.wait()
    return audio.failed ? nil : Unmanaged.passRetained(audio).toOpaque()
}
@_cdecl("vyrra_meeting_audio_read")
public func readAudio(_ handle: UnsafeMutableRawPointer, _ dest: UnsafeMutablePointer<Float>, _ capacity: Int32) -> Int32 {
    let source = Unmanaged<MeetingAudio>.fromOpaque(handle).takeUnretainedValue()
    source.lock.lock(); defer { source.lock.unlock() }
    guard !source.failed else { return -1 }
    let n = min(source.pcm.count, Int(capacity)); if n > 0 { source.pcm.withUnsafeBufferPointer { dest.update(from: $0.baseAddress!, count: n) }; source.pcm.removeFirst(n) }
    return Int32(n)
}
@_cdecl("vyrra_meeting_audio_close")
public func closeAudio(_ handle: UnsafeMutableRawPointer) {
    let source = Unmanaged<MeetingAudio>.fromOpaque(handle).takeRetainedValue()
    let done = DispatchSemaphore(value: 0)
    Task { try? await source.stream?.stopCapture(); source.stream = nil; done.signal() }
    done.wait()
}

import EventKit
private struct CalendarCall: Encodable {
    let uid: String, title: String, url: String
    let startMs: Int64, endMs: Int64
}
@_cdecl("vyrra_calendar_calls")
public func calendarCalls(_ prompt: Bool) -> UnsafeMutablePointer<CChar>? {
    let store = EKEventStore(), status = EKEventStore.authorizationStatus(for: .event)
    if status == .notDetermined && prompt {
        let done = DispatchSemaphore(value: 0)
        if #available(macOS 14, *) { store.requestFullAccessToEvents { _, _ in done.signal() } }
        else { store.requestAccess(to: .event) { _, _ in done.signal() } }
        done.wait()
    }
    if #available(macOS 14, *) { guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return nil } }
    else { guard EKEventStore.authorizationStatus(for: .event) == .authorized else { return nil } }
    let now = Date(), range = store.predicateForEvents(withStart: now.addingTimeInterval(-86400), end: now.addingTimeInterval(90*86400), calendars: nil)
    guard let links = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
    var rows = [CalendarCall]()
    for event in store.events(matching: range) where !event.isAllDay && event.status != .canceled && event.endDate > now {
        let guests = event.attendees ?? []
        guard guests.isEmpty || event.organizer?.isCurrentUser == true || guests.contains(where: { $0.isCurrentUser && $0.participantStatus == .accepted }) else { continue }
        let text = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }.joined(separator: "\n")
        for result in links.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = result.url, let host = url.host?.lowercased(), url.scheme == "https",
                  host == "meet.google.com" || host == "teams.microsoft.com" || host == "teams.cloud.microsoft" || host == "teams.live.com" || host == "zoom.us" || host.hasSuffix(".zoom.us") || host == "zoomgov.com" || host.hasSuffix(".zoomgov.com") else { continue }
            let occurrence = event.hasRecurrenceRules || event.isDetached ? String(Int64((event.occurrenceDate ?? event.startDate).timeIntervalSince1970)) : "single"
            let key = "apple:" + event.calendarItemIdentifier + "/" + occurrence
            rows.append(CalendarCall(uid: key, title: event.title ?? "Meeting", url: url.absoluteString, startMs: Int64(event.startDate.timeIntervalSince1970*1000), endMs: Int64(event.endDate.timeIntervalSince1970*1000)))
        }
    }
    guard let data = try? JSONEncoder().encode(rows), let json = String(data: data, encoding: .utf8) else { return nil }; return strdup(json)
}
@_cdecl("vyrra_calendar_free")
public func freeCalendar(_ value: UnsafeMutablePointer<CChar>) { free(value) }
