import AudioToolbox
import Foundation
import SwiftUI

@MainActor
enum DictationSound {
    nonisolated static let preferenceKey = "dictationSoundsEnabled"
    nonisolated static let paletteKey = "dictationSoundPalette"
    enum Palette: String, CaseIterable {
        case studio, classic, soft, felt, porcelain, off
        var label: String {
            switch self { case .studio: "Studio latch"; case .porcelain: "Porcelain"; case .classic: "Classic"; case .soft: "Soft click"; case .felt: "Felt thud"; case .off: "Off" }
        }
        func file(closing: Bool) -> String? {
            guard self != .off else { return nil }
            return (self == .classic ? "" : rawValue + "-") + (closing ? "release" : "engage")
        }
    }
    static func palette(in defaults: UserDefaults = .standard) -> Palette {
        guard (defaults.object(forKey: preferenceKey) as? Bool ?? true) else { return .off }
        return defaults.string(forKey: paletteKey).flatMap(Palette.init(rawValue:)) ?? .studio
    }
    private static var cached: [String: SystemSoundID] = [:]

    private static func load(_ name: String) -> SystemSoundID? {
        if let sound = cached[name] { return sound }
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "DictationSounds")
        else { return nil }
        var sound: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &sound) == noErr else { return nil }
        cached[name] = sound
        return sound
    }

    static func engageBeforeCapture() async {
        guard let file = palette().file(closing: false), let sound = load(file) else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var waiting: CheckedContinuation<Void, Never>? = continuation
            let finish: @MainActor @Sendable () -> Void = {
                waiting?.resume()
                waiting = nil
            }
            AudioServicesPlaySystemSoundWithCompletion(sound) { DispatchQueue.main.async { finish() } }
            // A silenced or interrupted system sound must never hold the microphone closed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { finish() }
        }
    }

    static func releaseAfterCapture() {
        guard let file = palette().file(closing: true), let releaseID = load(file) else { return }
        AudioServicesPlaySystemSound(releaseID)
    }
}

struct DictationSoundPicker: View {
    @AppStorage(DictationSound.preferenceKey) private var enabled = true
    @AppStorage(DictationSound.paletteKey) private var stored = DictationSound.Palette.studio.rawValue
    @State private var preview: Task<Void, Never>?
    @State private var playing = false
    private var selected: DictationSound.Palette { enabled ? DictationSound.Palette(rawValue: stored) ?? .studio : .off }
    var body: some View {
        HStack {
            Text("Dictation sound")
            Spacer()
            Button {
                guard !playing else { return }
                playing = true
                preview = Task { @MainActor in
                    defer { playing = false }
                    await DictationSound.engageBeforeCapture()
                    try? await Task.sleep(for: .milliseconds(150))
                    if !Task.isCancelled { DictationSound.releaseAfterCapture() }
                }
            } label: { Image(systemName: "speaker.wave.2").frame(minWidth: 44, minHeight: 44) }
            .buttonStyle(.plain).accessibilityLabel("Preview start and finish sounds").disabled(selected == .off || playing)
            Picker("Dictation sound", selection: Binding(get: { selected }, set: { value in
                preview?.cancel(); stored = value.rawValue; enabled = value != .off
            })) {
                ForEach(DictationSound.Palette.allCases, id: \.self) { Text($0.label).tag($0) }
            }.labelsHidden().pickerStyle(.menu)
        }.onDisappear { preview?.cancel() }
    }
}
