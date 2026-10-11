import SwiftUI

/// Библиотека текстов: категории → тексты. Нажатие на текст добавляет его в «Хочу записать».
struct TextLibraryView: View {
    @EnvironmentObject private var wishlist: Wishlist
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(TextLibrary.categories) { category in
                        NavigationLink(value: category) {
                            HStack {
                                Text(category.title)
                                Spacer()
                                let added = category.items.filter { wishlist.contains(sourceID: $0.id) }.count
                                Text(added > 0 ? "\(added) из \(category.items.count)" : "\(category.items.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                } footer: {
                    Text("Выберите тексты, которые хотите записать своим голосом. Они появятся в списке «Хочу записать».")
                }
            }
            .navigationTitle("Библиотека")
            .navigationDestination(for: TextCategory.self) { TextCategoryView(category: $0) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}

struct TextCategoryView: View {
    let category: TextCategory
    @EnvironmentObject private var wishlist: Wishlist

    var body: some View {
        List {
            Section {
                ForEach(category.items) { item in
                    let added = wishlist.contains(sourceID: item.id)
                    Button {
                        wishlist.toggle(item)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Text(item.text)
                                .foregroundStyle(Color.primary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                                .font(.title3)
                                .foregroundStyle(added ? Color.accentColor : Color.secondary)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.text)
                    .accessibilityValue(added ? "В списке «Хочу записать»" : "Не добавлено")
                    .accessibilityHint(added ? "Нажмите дважды, чтобы убрать из списка" : "Нажмите дважды, чтобы добавить в список «Хочу записать»")
                    .accessibilityAddTraits(.isButton)
                }
            } footer: {
                Text("Нажмите на текст, чтобы добавить его или убрать из списка «Хочу записать».")
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(allAdded ? "Убрать все" : "Добавить все") {
                    if allAdded { wishlist.removeAll(category.items) } else { wishlist.addAll(category.items) }
                }
                .accessibilityHint(allAdded ? "Уберёт все тексты этой категории из списка «Хочу записать»" : "Добавит все тексты этой категории в список «Хочу записать»")
            }
        }
    }

    private var allAdded: Bool {
        category.items.allSatisfy { wishlist.contains(sourceID: $0.id) }
    }
}

/// Тексты, ожидающие записи. Нажатие открывает окно записи с этим текстом.
struct WishlistView: View {
    var onRecord: (WishItem) -> Void
    @EnvironmentObject private var wishlist: Wishlist

    var body: some View {
        Group {
            if wishlist.items.isEmpty {
                ContentUnavailableView {
                    Label("Список пуст", systemImage: "text.badge.plus")
                } description: {
                    Text("Добавьте тексты из библиотеки, чтобы записать их позже.")
                }
            } else {
                List {
                    Section {
                        ForEach(wishlist.items) { item in
                            Button {
                                onRecord(item)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Text(item.text)
                                        .foregroundStyle(Color.primary)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "mic.fill")
                                        .foregroundStyle(Color.accentColor)
                                        .accessibilityHidden(true)
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.text)
                            .accessibilityHint("Нажмите дважды, чтобы записать")
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    wishlist.remove(id: item.id)
                                } label: {
                                    Label("Убрать", systemImage: "minus.circle")
                                }
                            }
                        }
                    } footer: {
                        Text("Нажмите на текст, чтобы записать его. Смахните влево, чтобы убрать из списка.")
                    }
                }
            }
        }
        .navigationTitle("Хочу записать")
        .navigationBarTitleDisplayMode(.inline)
    }
}
