import SwiftUI
import UniformTypeIdentifiers

struct SessionSettingsView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var music: MusicLibrary
    @Environment(\.dismiss) private var dismiss

    @State private var showImporter = false
    @State private var importError: String?
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Пауза между записями") {
                    Picker("Пауза между записями", selection: $settings.value.gapSeconds) {
                        ForEach(SessionSettings.gapOptions, id: \.self) { Text(Format.gapOption($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section("Таймер остановки") {
                    Picker("Таймер остановки", selection: $settings.value.timerSeconds) {
                        ForEach(SessionSettings.timerOptions, id: \.self) { Text(Format.timerOption($0)).tag($0) }
                    }
                    .pickerStyle(.menu)
                }

                Section("Громкость") {
                    VolumeRow(title: "Голос", icon: "person.wave.2", value: $settings.value.voiceVolume)
                    VolumeRow(title: "Музыка", icon: "music.note", value: $settings.value.musicVolume)
                }

                Section {
                    musicRow(title: "Без музыки", id: nil, imported: nil)
                    ForEach(music.allTracks) { track in
                        musicRow(title: track.title, id: track.id, imported: track)
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("Добавить из «Файлов»", systemImage: "plus")
                    }
                    .disabled(isImporting)
                } header: {
                    Text("Фоновая музыка")
                } footer: {
                    Text("Музыка звучит непрерывно и повторяется, в том числе в паузах между записями.")
                }
            }
            .navigationTitle("Настройки сессии")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    isImporting = true
                    Task {
                        let errors = await app.importMusic(from: urls)
                        isImporting = false
                        if !errors.isEmpty { importError = errors.joined(separator: "\n") }
                    }
                case .failure:
                    importError = "Не удалось открыть выбранный файл."
                }
            }
            .alert("Не удалось добавить", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("Понятно", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
        }
    }

    @ViewBuilder
    private func musicRow(title: String, id: String?, imported: MusicTrack?) -> some View {
        let selected = settings.value.musicTrackID == id
        Button {
            settings.value.musicTrackID = id
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "выбрано" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .swipeActions(edge: .trailing) {
            if let imported, imported.isImported {
                Button(role: .destructive) {
                    app.deleteMusic(imported)
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
            }
        }
    }
}

private struct VolumeRow: View {
    let title: String
    let icon: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary).accessibilityHidden(true)
                Slider(value: $value, in: 0...1)
                    .accessibilityLabel("Громкость: \(title)")
                    .accessibilityValue("\(Int((value * 100).rounded())) процентов")
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }
    }
}
