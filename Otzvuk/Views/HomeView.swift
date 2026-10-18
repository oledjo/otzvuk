import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var wishlist: Wishlist

    @State private var recorderRequest: RecorderRequest?
    @State private var showLibrary = false
    @State private var showSettings = false
    @State private var renaming: Affirmation?
    @State private var renameText = ""
    @State private var deleting: Affirmation?
    @State private var settingsDetent: PresentationDetent = .large

    var body: some View {
        NavigationStack {
            Group {
                if library.affirmations.isEmpty && wishlist.items.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Аффирмации")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showLibrary = true
                    } label: {
                        Image(systemName: "books.vertical")
                    }
                    .accessibilityLabel("Библиотека текстов")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Настройки сессии")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                BottomBar(onRecord: { openRecorder(nil) }, showSettings: $showSettings)
            }
        }
        .sheet(item: $recorderRequest) { request in
            RecordingView(wish: request.wish)
        }
        .sheet(isPresented: $showLibrary) {
            TextLibraryView()
        }
        .sheet(isPresented: $showSettings) {
            SessionSettingsView()
                .presentationDetents([.medium, .large], selection: $settingsDetent)
        }
        .alert("Переименовать", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Название", text: $renameText)
            Button("Сохранить") {
                if let item = renaming { library.rename(id: item.id, to: renameText) }
                renaming = nil
            }
            Button("Отмена", role: .cancel) { renaming = nil }
        }
        .confirmationDialog(
            "Удалить «\(deleting?.title ?? "")»?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let item = deleting { app.delete(item) }
                deleting = nil
            }
            Button("Отмена", role: .cancel) { deleting = nil }
        } message: {
            Text("Запись будет удалена без возможности восстановления.")
        }
        .alert("Otzvuk", isPresented: Binding(get: { app.alertMessage != nil }, set: { if !$0 { app.alertMessage = nil } })) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text(app.alertMessage ?? "")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Пока нет записей", systemImage: "waveform")
        } description: {
            Text("Нажмите кнопку записи и произнесите свою первую аффирмацию или выберите текст в библиотеке.")
        } actions: {
            Button("Открыть библиотеку") { showLibrary = true }
                .buttonStyle(.bordered)
        }
    }

    private var list: some View {
        List {
            if !wishlist.items.isEmpty {
                Section {
                    NavigationLink {
                        WishlistView(onRecord: { openRecorder($0) })
                    } label: {
                        HStack {
                            Label("Хочу записать", systemImage: "text.badge.plus")
                            Spacer()
                            Text("\(wishlist.items.count)").foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityValue("\(wishlist.items.count)")
                }
            }
            if !library.affirmations.isEmpty {
            Section {
                ReverseAllRow()
            } footer: {
                Text("Все выбранные записи будут звучать с конца к началу. Оригиналы не меняются.")
            }
            Section {
                ForEach(library.affirmations) { item in
                    AffirmationRow(item: item)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleting = item
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                            Button {
                                renameText = item.title
                                renaming = item
                            } label: {
                                Label("Переименовать", systemImage: "pencil")
                            }
                            .tint(.gray)
                        }
                        .contextMenu {
                            Button {
                                renameText = item.title
                                renaming = item
                            } label: {
                                Label("Переименовать", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deleting = item
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                }
            } footer: {
                Text("Отметьте записи для прослушивания. Смахните влево, чтобы переименовать или удалить.")
            }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func openRecorder(_ wish: WishItem?) {
        app.prepareForRecording()
        recorderRequest = RecorderRequest(wish: wish)
    }
}

// MARK: - Строка списка

struct AffirmationRow: View {
    let item: Affirmation
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var session: SessionPlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                library.toggleSelected(id: item.id)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(item.isSelected ? Color.accentColor : Color.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            if session.currentID == item.id {
                                Image(systemName: "speaker.wave.2.fill")
                                    .accessibilityHidden(true)
                            }
                            Text(Format.clock(item.duration))
                        }
                        .font(.footnote)
                        .foregroundStyle(session.currentID == item.id ? Color.accentColor : Color.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.title)
            .accessibilityValue(valueDescription)
            .accessibilityHint("Нажмите дважды, чтобы выбрать или снять выбор")
            .accessibilityAddTraits(.isButton)

        }
        .padding(.vertical, 6)
    }

    private var valueDescription: String {
        let selected = item.isSelected ? "выбрано" : "не выбрано"
        return "\(selected), \(Format.clock(item.duration))"
    }
}

/// Переключатель обратного воспроизведения для всего плейлиста.
struct ReverseAllRow: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Toggle(isOn: Binding(
            get: { settings.value.reversed },
            set: { app.setReversedForAll($0) }
        )) {
            HStack(spacing: 8) {
                Label("Задом наперёд", systemImage: "arrow.uturn.backward")
                if !app.preparing.isEmpty {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Подготовка записей")
                }
            }
        }
        .tint(.accentColor)
        .accessibilityLabel("Задом наперёд, все записи")
    }
}

// MARK: - Нижняя панель

struct BottomBar: View {
    var onRecord: () -> Void
    @Binding var showSettings: Bool

    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var music: MusicLibrary
    @EnvironmentObject private var session: SessionPlayer

    var body: some View {
        VStack(spacing: 12) {
            if session.isActive {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        recordButton
                        MiniPlayer(showSettings: $showSettings)
                    }
                    VStack(spacing: 12) {
                        MiniPlayer(showSettings: $showSettings)
                        recordButton
                    }
                }
            } else {
                if !library.affirmations.isEmpty {
                    Button {
                        showSettings = true
                    } label: {
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Настройки сессии: \(summary)")
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        recordButton
                        listenButton
                    }
                    VStack(spacing: 12) {
                        listenButton
                        recordButton
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
        // Панель не должна съедать экран при огромном шрифте; сам список масштабируется полностью.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var recordButton: some View {
        Button {
            onRecord()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Circle().fill(Color.accentColor))
        }
        .accessibilityLabel("Добавить запись")
    }

    private var listenButton: some View {
        let count = library.selected.count
        return Button {
            app.startSession()
        } label: {
            HStack {
                Image(systemName: "play.fill")
                Text(count > 0 ? "Слушать · \(count)" : "Слушать")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .disabled(count == 0)
        .accessibilityLabel("Слушать")
        .accessibilityValue(count > 0 ? "Выбрано \(count) \(Format.plural(count, "запись", "записи", "записей"))" : "Сначала выберите записи")
    }

    private var summary: String {
        let s = settings.value
        let musicName = music.track(id: s.musicTrackID)?.title ?? "Без музыки"
        let reversed = s.reversed ? " · Задом наперёд" : ""
        return "\(Format.gap(s.gapSeconds)) · \(Format.timer(s.timerSeconds)) · \(musicName)\(reversed)"
    }
}

// MARK: - Компактный плеер

struct MiniPlayer: View {
    @Binding var showSettings: Bool
    @EnvironmentObject private var session: SessionPlayer

    var body: some View {
        HStack(spacing: 8) {
            Button {
                showSettings = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.currentTitle.isEmpty ? "Otzvuk" : session.currentTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Сейчас: \(session.currentTitle)")
            .accessibilityValue(status)
            .accessibilityHint("Откроет настройки сессии")
            .accessibilityAddTraits(.isButton)

            Button {
                session.togglePlayPause()
            } label: {
                Image(systemName: session.state == .playing ? "pause.fill" : "play.fill")
                    .frame(width: 40, height: 40)
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityLabel(session.state == .playing ? "Пауза" : "Продолжить")

            Button {
                session.next()
            } label: {
                Image(systemName: "forward.fill")
                    .frame(width: 40, height: 40)
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityLabel("Следующая запись")

            Button {
                session.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 40, height: 40)
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityLabel("Остановить")
        }
        .font(.title3)
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private var status: String {
        var parts: [String] = []
        if session.isFadingOut {
            parts.append("Затухание")
        } else if session.isPreparing {
            parts.append("Подготовка")
        } else if session.state == .paused {
            parts.append("Пауза")
        } else if session.isInGap {
            parts.append("Пауза между записями")
        } else {
            parts.append("Звучит")
        }
        if let left = session.timerRemaining, !session.isFadingOut {
            parts.append("осталось \(Format.clock(TimeInterval(left)))")
        }
        return parts.joined(separator: " · ")
    }
}
