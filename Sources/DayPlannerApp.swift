//
//  DayPlannerApp.swift
//  Распорядок дня + To-Do
//
//  Требования: Xcode 26+ (или 27 beta), iOS 26.0+ (Liquid Glass).
//  Установка: создайте проект iOS App (SwiftUI), удалите стандартные
//  ContentView.swift и <Имя>App.swift, добавьте этот файл.
//

import SwiftUI

// MARK: - Приложение

@main
struct DayPlannerApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environment(\.locale, Locale(identifier: "ru_RU"))
                .environment(\.calendar, Calendar.planner)
        }
    }
}

// MARK: - Календарь и форматирование

extension Calendar {
    /// Григорианский календарь, неделя начинается с понедельника
    static let planner: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "ru_RU")
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }()
}

private let cal = Calendar.planner

/// Порядок дней недели (Calendar.weekday: 1 = Вс, 2 = Пн ... 7 = Сб)
let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

func shortWeekday(_ wd: Int) -> String {
    ["", "Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"][wd]
}

func durationText(_ minutes: Int) -> String {
    let h = minutes / 60
    let m = minutes % 60
    if h == 0 { return "\(m) мин" }
    if m == 0 { return "\(h) ч" }
    return "\(h) ч \(m) мин"
}

enum Fmt {
    static func string(_ date: Date, _ template: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.calendar = cal
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: date)
    }

    static func time(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}

extension String {
    var capFirst: String { prefix(1).uppercased() + String(dropFirst()) }
}

extension Date {
    var startOfDay: Date { cal.startOfDay(for: self) }
    var weekday: Int { cal.component(.weekday, from: self) }

    func addingDays(_ n: Int) -> Date {
        cal.date(byAdding: .day, value: n, to: self) ?? self
    }

    /// 7 дней недели (с понедельника), в которую входит дата
    var weekDays: [Date] {
        let start = cal.dateInterval(of: .weekOfYear, for: self)?.start ?? self
        return (0..<7).map { start.addingDays($0) }
    }
}

// MARK: - Модели

enum RoutineKind: String, Codable, CaseIterable, Identifiable {
    case wake, meal, sport, work, free, sleep, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wake: "Подъём"
        case .meal: "Приём пищи"
        case .sport: "Спорт"
        case .work: "Работа"
        case .free: "Свободное время"
        case .sleep: "Отбой"
        case .other: "Другое"
        }
    }

    var icon: String {
        switch self {
        case .wake: "sunrise.fill"
        case .meal: "fork.knife"
        case .sport: "figure.run"
        case .work: "briefcase.fill"
        case .free: "gamecontroller.fill"
        case .sleep: "moon.zzz.fill"
        case .other: "star.fill"
        }
    }

    var color: Color {
        switch self {
        case .wake: Color.orange
        case .meal: Color.green
        case .sport: Color.red
        case .work: Color.blue
        case .free: Color.purple
        case .sleep: Color.indigo
        case .other: Color.gray
        }
    }
}

struct ScheduleItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var kind: RoutineKind
    var start: Int          // минуты от полуночи
    var duration: Int       // минуты (0 = без длительности)
    var weekdays: Set<Int>  // Calendar.weekday

    var end: Int { start + duration }
}

struct TodoItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var date: Date
    var isDone = false
}

// MARK: - Хранилище (JSON в Documents)

final class Store: ObservableObject {
    @Published private(set) var schedule: [ScheduleItem] = []
    @Published private(set) var todos: [TodoItem] = []

    private struct Snapshot: Codable {
        var schedule: [ScheduleItem]
        var todos: [TodoItem]
    }

    private let url = URL.documentsDirectory.appending(path: "planner.json")

    init() {
        if let data = try? Data(contentsOf: url),
           let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            schedule = snap.schedule
            todos = snap.todos
        } else {
            schedule = Self.sample()
            save()
        }
    }

    // Распорядок

    func items(forWeekday wd: Int) -> [ScheduleItem] {
        schedule.filter { $0.weekdays.contains(wd) }.sorted { $0.start < $1.start }
    }

    func upsert(_ item: ScheduleItem) {
        if let i = schedule.firstIndex(where: { $0.id == item.id }) {
            schedule[i] = item
        } else {
            schedule.append(item)
        }
        save()
    }

    /// Убирает пункт только из выбранного дня недели
    func remove(_ item: ScheduleItem, fromWeekday wd: Int) {
        guard let i = schedule.firstIndex(where: { $0.id == item.id }) else { return }
        schedule[i].weekdays.remove(wd)
        if schedule[i].weekdays.isEmpty { schedule.remove(at: i) }
        save()
    }

    func removeEverywhere(_ item: ScheduleItem) {
        schedule.removeAll { $0.id == item.id }
        save()
    }

    // To-Do

    func todos(on date: Date) -> [TodoItem] {
        todos.filter { cal.isDate($0.date, inSameDayAs: date) }
    }

    func addTodo(_ title: String, on date: Date) {
        todos.append(TodoItem(title: title, date: date.startOfDay))
        save()
    }

    func toggle(_ todo: TodoItem) {
        guard let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[i].isDone.toggle()
        save()
    }

    func delete(_ todo: TodoItem) {
        todos.removeAll { $0.id == todo.id }
        save()
    }

    // Сохранение

    private func save() {
        let snap = Snapshot(schedule: schedule, todos: todos)
        do {
            try JSONEncoder().encode(snap).write(to: url, options: .atomic)
        } catch {
            print("Save error:", error)
        }
    }

    private static func sample() -> [ScheduleItem] {
        let all = Set(1...7)
        let work: Set<Int> = [2, 3, 4, 5, 6]
        return [
            ScheduleItem(title: "Подъём", kind: .wake, start: 7 * 60, duration: 0, weekdays: all),
            ScheduleItem(title: "Завтрак", kind: .meal, start: 7 * 60 + 30, duration: 30, weekdays: all),
            ScheduleItem(title: "Работа", kind: .work, start: 9 * 60, duration: 240, weekdays: work),
            ScheduleItem(title: "Обед", kind: .meal, start: 13 * 60, duration: 45, weekdays: all),
            ScheduleItem(title: "Работа", kind: .work, start: 14 * 60, duration: 240, weekdays: work),
            ScheduleItem(title: "Спорт", kind: .sport, start: 18 * 60 + 30, duration: 60, weekdays: [2, 4, 6]),
            ScheduleItem(title: "Свободное время", kind: .free, start: 20 * 60, duration: 90, weekdays: all),
            ScheduleItem(title: "Отбой", kind: .sleep, start: 23 * 60, duration: 0, weekdays: all)
        ]
    }
}

// MARK: - Корневой экран: 3 вкладки со свайпом

struct RootView: View {
    @State private var tab = 1   // по умолчанию — центральная

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                CalendarTab().tag(0)   // свайп вправо
                ScheduleTab().tag(1)
                TodoTab().tag(2)       // свайп влево
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(.container, edges: .bottom)

            GlassTabBar(selection: $tab)
        }
        .sensoryFeedback(.selection, trigger: tab)
    }
}

/// Нижний переключатель в стиле Liquid Glass
struct GlassTabBar: View {
    @Binding var selection: Int
    @Namespace private var ns

    private let items: [(title: String, icon: String)] = [
        ("Календарь", "calendar"),
        ("Распорядок", "clock"),
        ("Задачи", "checklist")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                let selected = selection == i
                Button {
                    withAnimation(.snappy) { selection = i }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: items[i].icon)
                            .font(.system(size: 20, weight: .semibold))
                            .symbolVariant(selected ? .fill : .none)
                        Text(items[i].title)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if selected {
                            Capsule()
                                .fill(Color.accentColor.opacity(0.16))
                                .matchedGeometryEffect(id: "pill", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }
}

// MARK: - Полоса выбора дня недели (общая)

struct WeekStrip: View {
    @Binding var date: Date

    var body: some View {
        let days = date.weekDays

        VStack(spacing: 10) {
            HStack {
                Button { shift(-7) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.small)

                Spacer()

                Text("\(Fmt.string(days[0], "d MMM")) – \(Fmt.string(days[6], "d MMM"))")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button { shift(7) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
            }

            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(days, id: \.self) { day in
                        chip(for: day)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func chip(for day: Date) -> some View {
        let selected = cal.isDate(day, inSameDayAs: date)
        let isToday = cal.isDateInToday(day)
        let glass: Glass = selected
            ? Glass.regular.tint(Color.accentColor).interactive()
            : Glass.regular.interactive()

        return Button {
            withAnimation(.snappy) { date = day.startOfDay }
        } label: {
            VStack(spacing: 3) {
                Text(Fmt.string(day, "EEEEEE").capFirst)
                    .font(.caption2.weight(.semibold))
                Text("\(cal.component(.day, from: day))")
                    .font(.title3.weight(.semibold).monospacedDigit())
                Circle()
                    .fill(isToday ? (selected ? Color.white : Color.accentColor) : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .glassEffect(glass, in: .rect(cornerRadius: 18))
    }

    private func shift(_ days: Int) {
        withAnimation(.snappy) { date = date.addingDays(days) }
    }
}

// MARK: - Центральная вкладка: распорядок дня

struct EditorTarget: Identifiable {
    let id = UUID()
    var item: ScheduleItem?
    var weekday: Int
}

struct ScheduleTab: View {
    @EnvironmentObject private var store: Store
    @State private var date = Date().startOfDay
    @State private var editor: EditorTarget?

    var body: some View {
        let items = store.items(forWeekday: date.weekday)

        NavigationStack {
            VStack(spacing: 0) {
                WeekStrip(date: $date)

                List {
                    ForEach(items) { item in
                        Button {
                            editor = EditorTarget(item: item, weekday: date.weekday)
                        } label: {
                            ScheduleRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.remove(item, fromWeekday: date.weekday)
                            } label: {
                                Label("Убрать", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .contentMargins(.bottom, 100, for: .scrollContent)
                .overlay {
                    if items.isEmpty {
                        ContentUnavailableView(
                            "Распорядок пуст",
                            systemImage: "clock",
                            description: Text("Нажмите «+», чтобы добавить пункт на этот день")
                        )
                    }
                }
            }
            .navigationTitle(Fmt.string(date, "EEEE").capFirst)
            .navigationSubtitle(Fmt.string(date, "d MMMM"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Сегодня") {
                        withAnimation(.snappy) { date = Date().startOfDay }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editor = EditorTarget(item: nil, weekday: date.weekday)
                    } label: {
                        Label("Добавить", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(item: $editor) { target in
            ScheduleEditor(item: target.item, weekday: target.weekday)
        }
    }
}

struct ScheduleRow: View {
    let item: ScheduleItem

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.time(item.start))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                if item.duration > 0 {
                    Text(Fmt.time(item.end))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 48, alignment: .trailing)

            Image(systemName: item.kind.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(item.kind.color.gradient, in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        item.duration > 0
            ? "\(item.kind.title) · \(durationText(item.duration))"
            : item.kind.title
    }
}

// MARK: - Добавление / редактирование пункта распорядка

struct ScheduleEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    private let original: ScheduleItem?
    @State private var title: String
    @State private var kind: RoutineKind
    @State private var time: Date
    @State private var duration: Int
    @State private var weekdays: Set<Int>

    private static let durations = [0, 15, 30, 45, 60, 90, 120, 180, 240, 360, 480]

    init(item: ScheduleItem?, weekday: Int) {
        original = item
        _title = State(initialValue: item?.title ?? "")
        _kind = State(initialValue: item?.kind ?? .other)
        _time = State(initialValue: Self.date(fromMinutes: item?.start ?? 9 * 60))
        _duration = State(initialValue: item?.duration ?? 30)
        _weekdays = State(initialValue: item?.weekdays ?? [weekday])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название", text: $title)
                }

                Section("Категория") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(RoutineKind.allCases) { k in
                                Button { pick(k) } label: {
                                    Label(k.title, systemImage: k.icon)
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .foregroundStyle(kind == k ? Color.white : k.color)
                                        .background(kind == k ? k.color : k.color.opacity(0.15), in: .capsule)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }

                Section("Время") {
                    DatePicker("Начало", selection: $time, displayedComponents: .hourAndMinute)
                    Picker("Длительность", selection: $duration) {
                        ForEach(Self.durations, id: \.self) { d in
                            Text(d == 0 ? "Без длительности" : durationText(d)).tag(d)
                        }
                    }
                }

                Section("Повторять по дням") {
                    HStack(spacing: 6) {
                        ForEach(weekdayOrder, id: \.self) { wd in
                            let on = weekdays.contains(wd)
                            Button {
                                if on { weekdays.remove(wd) } else { weekdays.insert(wd) }
                            } label: {
                                Text(shortWeekday(wd))
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .foregroundStyle(on ? Color.white : Color.primary)
                                    .background(
                                        on ? Color.accentColor : Color.secondary.opacity(0.15),
                                        in: .rect(cornerRadius: 10)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

                    HStack {
                        Button("Каждый день") { weekdays = Set(1...7) }
                        Button("Будни") { weekdays = [2, 3, 4, 5, 6] }
                        Button("Выходные") { weekdays = [1, 7] }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let original {
                    Section {
                        Button("Удалить из всех дней", role: .destructive) {
                            store.removeEverywhere(original)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(original == nil ? "Новый пункт" : "Изменить")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !weekdays.isEmpty
    }

    private func pick(_ k: RoutineKind) {
        if title.isEmpty || title == kind.title { title = k.title }
        if original == nil, k == .wake || k == .sleep { duration = 0 }
        kind = k
    }

    private func save() {
        let comps = cal.dateComponents([.hour, .minute], from: time)
        let start = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)

        var item = original ?? ScheduleItem(
            title: "", kind: kind, start: start, duration: duration, weekdays: weekdays
        )
        item.title = title.trimmingCharacters(in: .whitespaces)
        item.kind = kind
        item.start = start
        item.duration = duration
        item.weekdays = weekdays

        store.upsert(item)
        dismiss()
    }

    private static func date(fromMinutes m: Int) -> Date {
        cal.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
    }
}

// MARK: - Правая вкладка: To-Do

struct TodoTab: View {
    @EnvironmentObject private var store: Store
    @State private var date = Date().startOfDay
    @State private var adding = false

    var body: some View {
        let todos = store.todos(on: date)
        let done = todos.filter(\.isDone).count

        NavigationStack {
            VStack(spacing: 0) {
                WeekStrip(date: $date)

                List {
                    if !todos.isEmpty {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Выполнено")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("\(done) из \(todos.count)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                ProgressView(value: Double(done), total: Double(todos.count))
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    ForEach(todos) { todo in
                        TodoRow(todo: todo)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    withAnimation { store.delete(todo) }
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                    }
                }
                .contentMargins(.bottom, 100, for: .scrollContent)
                .overlay {
                    if todos.isEmpty {
                        ContentUnavailableView(
                            "Нет задач",
                            systemImage: "checklist",
                            description: Text("Нажмите «+», чтобы добавить задачу на этот день")
                        )
                    }
                }
            }
            .navigationTitle(cal.isDateInToday(date) ? "Сегодня" : Fmt.string(date, "EEEE").capFirst)
            .navigationSubtitle(Fmt.string(date, "d MMMM"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Сегодня") {
                        withAnimation(.snappy) { date = Date().startOfDay }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: {
                        Label("Добавить", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $adding) {
            AddTodoSheet(date: date)
        }
    }
}

struct TodoRow: View {
    @EnvironmentObject private var store: Store
    let todo: TodoItem

    var body: some View {
        Button {
            withAnimation(.snappy) { store.toggle(todo) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(todo.isDone ? Color.green : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                Text(todo.title)
                    .strikethrough(todo.isDone)
                    .foregroundStyle(todo.isDone ? .secondary : .primary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: todo.isDone)
    }
}

struct AddTodoSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    let date: Date
    @State private var text = ""
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Что нужно сделать?", text: $text)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(add)
                    .padding(14)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))

                Button(action: add) {
                    Label("Добавить", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(trimmed.isEmpty)

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle(Fmt.string(date, "EEEE, d MMMM").capFirst)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(240), .medium])
        .onAppear { focused = true }
    }

    private func add() {
        guard !trimmed.isEmpty else { return }
        store.addTodo(trimmed, on: date)
        text = ""
        focused = true
    }
}

// MARK: - Левая вкладка: календарь на год

struct DaySelection: Identifiable {
    let date: Date
    var id: Date { date }
}

struct CalendarTab: View {
    @State private var year = cal.component(.year, from: Date())
    @State private var selected: DaySelection?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 22) {
                        ForEach(1...12, id: \.self) { m in
                            MonthView(year: year, month: m) { selected = DaySelection(date: $0) }
                                .id(m)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                }
                .contentMargins(.bottom, 100, for: .scrollContent)
                .onAppear { scrollToCurrent(proxy) }
                .onChange(of: year) { _, _ in scrollToCurrent(proxy) }
            }
            .navigationTitle(String(year))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Сегодня") {
                        year = cal.component(.year, from: Date())
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { year -= 1 } label: { Image(systemName: "chevron.left") }
                    Button { year += 1 } label: { Image(systemName: "chevron.right") }
                }
            }
        }
        .sheet(item: $selected) { sel in
            DayDetailSheet(date: sel.date)
        }
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy) {
        let now = Date()
        let target = year == cal.component(.year, from: now) ? cal.component(.month, from: now) : 1
        withAnimation { proxy.scrollTo(target, anchor: .top) }
    }
}

struct MonthView: View {
    let year: Int
    let month: Int
    let onSelect: (Date) -> Void

    private var first: Date {
        cal.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
    }

    private var isCurrentMonth: Bool {
        let now = Date()
        return cal.component(.year, from: now) == year && cal.component(.month, from: now) == month
    }

    var body: some View {
        let offset = (first.weekday - cal.firstWeekday + 7) % 7
        let count = cal.range(of: .day, in: .month, for: first)?.count ?? 30

        VStack(alignment: .leading, spacing: 8) {
            Text(Fmt.string(first, "LLLL").capFirst)
                .font(.title2.bold())
                .foregroundStyle(isCurrentMonth ? Color.accentColor : Color.primary)
                .padding(.horizontal, 4)

            HStack(spacing: 2) {
                ForEach(weekdayOrder, id: \.self) { wd in
                    Text(shortWeekday(wd))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(0..<offset, id: \.self) { _ in
                    Color.clear.frame(height: 1)
                }
                ForEach(1...count, id: \.self) { d in
                    let date = cal.date(from: DateComponents(year: year, month: month, day: d)) ?? first
                    DayCell(date: date) { onSelect(date) }
                }
            }
        }
    }
}

struct DayCell: View {
    @EnvironmentObject private var store: Store
    let date: Date
    let action: () -> Void

    var body: some View {
        let todos = store.todos(on: date)
        let isToday = cal.isDateInToday(date)

        Button(action: action) {
            VStack(spacing: 3) {
                Text("\(cal.component(.day, from: date))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isToday ? Color.white : Color.primary)
                    .frame(width: 22, height: 22)
                    .background {
                        if isToday { Circle().fill(Color.accentColor) }
                    }

                VStack(alignment: .leading, spacing: 1) {
                    ForEach(todos.prefix(3)) { t in
                        Text(t.title)
                            .font(.system(size: 8.5, weight: .medium))
                            .lineLimit(1)
                            .strikethrough(t.isDone)
                            .foregroundStyle(t.isDone ? .tertiary : .primary)
                            .padding(.horizontal, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                Color.accentColor.opacity(t.isDone ? 0.07 : 0.18),
                                in: .rect(cornerRadius: 3)
                            )
                    }
                    if todos.count > 3 {
                        Text("+\(todos.count - 3)")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 2)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 4)
            .padding(.horizontal, 2)
            .padding(.bottom, 3)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .top)
            .background(.quaternary, in: .rect(cornerRadius: 8))
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Детали дня: дела + распорядок этого дня недели
struct DayDetailSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    let date: Date
    @State private var newTitle = ""

    var body: some View {
        let todos = store.todos(on: date)
        let routine = store.items(forWeekday: date.weekday)

        NavigationStack {
            List {
                Section("Дела") {
                    ForEach(todos) { todo in
                        TodoRow(todo: todo)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    withAnimation { store.delete(todo) }
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                        TextField("Новое дело", text: $newTitle)
                            .submitLabel(.done)
                            .onSubmit(add)
                    }
                }

                if !routine.isEmpty {
                    Section("Распорядок дня") {
                        ForEach(routine) { item in
                            ScheduleRow(item: item)
                        }
                    }
                }
            }
            .navigationTitle(Fmt.string(date, "EEEE, d MMMM").capFirst)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func add() {
        let t = newTitle.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        store.addTodo(t, on: date)
        newTitle = ""
    }
}

