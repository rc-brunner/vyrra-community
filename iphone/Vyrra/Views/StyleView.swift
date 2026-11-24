import SwiftUI

struct StyleView: View {
    @EnvironmentObject private var modelManager: ModelManager
    @Environment(\.vyrraAccentColor) private var accentColor
    @AppStorage(VyrraAccent.storageKey) private var accentRawValue = VyrraAccent.monochrome.rawValue
    @AppStorage(DictationSound.preferenceKey) private var dictationSoundsEnabled = true

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VyrraPanel {
                        VStack(alignment: .leading, spacing: 14) {
                            StyleSectionHeader(title: "Accent", icon: "paintpalette")

                            VyrraAccentPicker(selection: $accentRawValue)
                        }
                    }

                    VyrraPanel {
                        VStack(alignment: .leading, spacing: 14) {
                            StyleSectionHeader(title: "Polish", icon: "sparkles")

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 142), spacing: 10)], spacing: 10) {
                                ForEach(PolishingMode.allCases) { mode in
                                    StylePresetButton(
                                        mode: mode,
                                        isSelected: modelManager.polishingMode == mode,
                                        accentColor: accentColor
                                    ) {
                                        modelManager.polishingMode = mode
                                        HapticManager.selected()
                                    }
                                }
                            }
                        }
                    }

                    VyrraPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            StyleSectionHeader(title: "Speech", icon: "globe")

                            HStack {
                                Text("Model")
                                    .foregroundStyle(.primary)

                                Spacer()

                                Picker("Model", selection: $modelManager.selectedModel) {
                                    ForEach(SpeechModel.allCases) { model in
                                        Text(model.title).tag(model)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(.secondary)
                            }

                            Divider()
                            HStack {
                                Text("Language")
                                    .foregroundStyle(.primary)

                                Spacer()

                                Picker("Language", selection: $modelManager.selectedLanguageCode) {
                                    ForEach(SpeechLanguage.allCases) { language in
                                        Text(language.title)
                                            .tag(language.rawValue)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(.secondary)
                            }

                            Text("Choose the language you speak. Auto Detect guesses each recording; a fixed language is more reliable for short phrases.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VyrraPanel {
                        VStack(alignment: .leading, spacing: 14) {
                            StyleSectionHeader(title: "Feedback", icon: "waveform")

                            VyrraWaveformPill(
                                level: 0.42 * modelManager.waveformSensitivity,
                                isActive: true,
                                motion: modelManager.waveformMotion,
                                accessibilityDescription: "Waveform preview"
                            )

                            Picker("Wave Motion", selection: $modelManager.waveformMotion) {
                                ForEach(WaveformMotion.allCases) { motion in
                                    Text(motion.title).tag(motion)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(minHeight: 44)

                            HStack {
                                Text("Wave Sensitivity")
                                Spacer()
                                Text(modelManager.waveformSensitivityLabel)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.body)

                            Slider(value: $modelManager.waveformSensitivity, in: 0.65...1.65, step: 0.05) {
                                Text("Wave Sensitivity")
                            } minimumValueLabel: {
                                Image(systemName: "waveform")
                                    .foregroundStyle(.secondary)
                            } maximumValueLabel: {
                                Image(systemName: "waveform.path.ecg")
                                    .foregroundStyle(.secondary)
                            }
                            .tint(accentColor)

                            Toggle("Haptic Feedback", isOn: $modelManager.hapticsEnabled)
                                .font(.body)
                            Toggle("Dictation Sounds", isOn: $dictationSoundsEnabled)
                                .font(.body)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 52)
            }
            .background(VyrraTheme.pageBackground)
            .navigationTitle("Output")
        }
    }
}

private struct StyleSectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
        }
        .font(.headline)
    }
}

private struct StylePresetButton: View {
    let mode: PolishingMode
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 22, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: 4)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(accentColor)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(isSelected ? accentColor.opacity(0.11) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: VyrraTheme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: VyrraTheme.cornerRadius, style: .continuous)
                    .stroke(isSelected ? accentColor.opacity(0.32) : VyrraTheme.thinLine, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch mode {
        case .raw:
            "text.alignleft"
        case .cleanUp:
            "sparkles"
        case .casual:
            "message"
        case .notes:
            "note.text"
        case .email:
            "envelope"
        case .bullets:
            "list.bullet"
        }
    }

    private var description: String {
        switch mode {
        case .raw:
            "Verbatim"
        case .cleanUp:
            "Filler, spacing"
        case .casual:
            "Conversational"
        case .notes:
            "Paragraphs"
        case .email:
            "Email-ready"
        case .bullets:
            "List format"
        }
    }
}

#Preview {
    StyleView()
        .environmentObject(ModelManager())
}
