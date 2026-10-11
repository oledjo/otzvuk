import SwiftUI

struct RecordingView: View {
    /// Текст из «хочу записать»: показывается над кнопкой записи, из него берётся название.
    var wish: WishItem? = nil

    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var recorder: VoiceRecorder
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var title = ""
    @State private var confirmDiscard = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
            // ScrollView: клавиатура уменьшает видимую область, а не сдвигает окно под навигационную панель.
            ScrollView {
            VStack(spacing: 28) {
                TextField("Название", text: $title)
                    .focused($titleFocused)
                    .submitLabel(.done)
                    .onSubmit { titleFocused = false }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemBackground)))
                    .accessibilityLabel("Название записи")

                if let wish {
                    Text(wish.text)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.accentColor.opacity(0.1)))
                        .accessibilityLabel("Текст для записи: \(wish.text)")
                }

                Spacer(minLength: 0)

                Text(Format.clock(recorder.elapsed))
                    .font(.system(.largeTitle, design: .rounded).weight(.light))
                    .monospacedDigit()
                    .accessibilityLabel("Длительность")
                    .accessibilityValue(Format.clock(recorder.elapsed))

                ProgressView(value: recorder.isPreviewing ? recorder.previewProgress : 0)
                    .opacity(recorder.isPreviewing ? 1 : 0)
                    .padding(.horizontal, 40)
                    .accessibilityHidden(true)

                mainButton

                Text(hint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 56, alignment: .top)

                if recorder.permissionDenied {
                    permissionBlock
                }

                if let message = recorder.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                // Место под кнопки резервируется всегда, чтобы главная кнопка не прыгала.
                actions
                    .opacity(recorder.state == .recorded ? 1 : 0)
                    .disabled(recorder.state != .recorded)
                    .accessibilityHidden(recorder.state != .recorded)
            }
            .padding(20)
            .frame(minHeight: proxy.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Новая запись")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        if recorder.hasTake { confirmDiscard = true } else { close() }
                    }
                }
            }
            .confirmationDialog("Удалить эту запись?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Удалить запись", role: .destructive) { close() }
                Button("Продолжить", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(recorder.hasTake)
        .onAppear {
            if title.isEmpty { title = wish?.suggestedTitle ?? library.nextDefaultTitle() }
        }
        .onDisappear { recorder.discard() }
        .presentationDetents([.large])
    }

    // MARK: - Элементы

    private var mainButton: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 168, height: 168)
                .scaleEffect(recorder.state == .recording ? 0.7 + 0.3 * recorder.level : 0.7)
                .animation(.easeOut(duration: 0.1), value: recorder.level)

            Button {
                titleFocused = false
                switch recorder.state {
                case .idle: Task { await recorder.startRecording() }
                case .recording: recorder.stopRecording()
                case .recorded: recorder.togglePreview()
                }
            } label: {
                Image(systemName: mainIcon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 96, height: 96)
                    .background(Circle().fill(Color.accentColor))
            }
            .accessibilityLabel(mainLabel)
        }
        .frame(height: 176)
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { rerecordButton; saveButton }
            VStack(spacing: 12) { saveButton; rerecordButton }
        }
    }

    private var rerecordButton: some View {
        Button {
            recorder.discard()
            Task { await recorder.startRecording() }
        } label: {
            Label("Перезаписать", systemImage: "arrow.counterclockwise")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }

    private var saveButton: some View {
        Button {
            app.saveRecording(title: title, wish: wish)
            dismiss()
        } label: {
            Text("Сохранить")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }

    private var permissionBlock: some View {
        VStack(spacing: 10) {
            Text("Нет доступа к микрофону. Разрешите его в настройках, чтобы записывать аффирмации.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Открыть настройки") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.bordered)
        }
    }

    private var mainIcon: String {
        switch recorder.state {
        case .idle: return "mic.fill"
        case .recording: return "stop.fill"
        case .recorded: return recorder.isPreviewing ? "pause.fill" : "play.fill"
        }
    }

    private var mainLabel: String {
        switch recorder.state {
        case .idle: return "Начать запись"
        case .recording: return "Остановить запись"
        case .recorded: return recorder.isPreviewing ? "Остановить прослушивание" : "Прослушать запись"
        }
    }

    private var hint: String {
        switch recorder.state {
        case .idle: return "Нажмите, чтобы начать запись"
        case .recording: return "Говорите. Нажмите, чтобы остановить"
        case .recorded: return recorder.isPreviewing ? "Идёт прослушивание" : "Прослушайте запись, затем сохраните или перезапишите"
        }
    }

    private func close() {
        recorder.discard()
        dismiss()
    }
}
