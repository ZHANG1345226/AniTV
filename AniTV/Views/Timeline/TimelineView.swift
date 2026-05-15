//
//  TimelineView.swift
//  AniTV
//
//  Created by Codex on 2026/4/9.
//

import Foundation
import Combine
import SwiftUI
import Kingfisher
import SQLiteData
import Dependencies

@MainActor
final class TimelineStore: ObservableObject {
    @Published private(set) var timeline: TimelineDayMap = [:]
    @Published private(set) var orderedDays: [String] = []
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage = ""

    private let service = TimelineService()
    private var hasLoaded = false

    func loadIfNeeded(database: any DatabaseWriter) async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await load(database: database)
    }

    func load(database: any DatabaseWriter) async {
        isLoading = true
        errorMessage = ""

        do {
            let map = try await service.fetchTimelineMap(database: database)
            timeline = map
            orderedDays = map.keys.sorted()
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            hasLoaded = false
        }
    }
}

struct TimelineView: View {
    let focusRestoreToken: Int
    @Binding var lastFocusedEntryID: String?
    @Binding var pendingRestoreEntryID: String?
    let openAnimeDetail: (Int) -> Void

    @StateObject private var store = TimelineStore()
    @Dependency(\.defaultDatabase) private var database

    var body: some View {
        Group {
            if store.isLoading {
                ProgressView()
                    .tint(.white)
            } else if !store.errorMessage.isEmpty {
                ContentUnavailableView(
                    "时间线加载失败",
                    systemImage: "exclamationmark.triangle",
                    description: Text(store.errorMessage)
                )
            } else if store.orderedDays.isEmpty {
                ContentUnavailableView(
                    "暂无时间线数据",
                    systemImage: "calendar"
                )
            } else {
                TimelineBoardView(
                    orderedDays: store.orderedDays,
                    timeline: store.timeline,
                    focusRestoreToken: focusRestoreToken,
                    lastFocusedEntryID: $lastFocusedEntryID,
                    pendingRestoreEntryID: $pendingRestoreEntryID,
                    openAnimeDetail: openAnimeDetail
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.07, blue: 0.12),
                    Color(red: 0.02, green: 0.03, blue: 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .task {
            TimelinePosterCache.configureIfNeeded()
            await store.loadIfNeeded(database: database)
        }
    }
}

private enum TimelinePosterCache {
    private static var didConfigure = false

    static func configureIfNeeded() {
        guard !didConfigure else { return }
        didConfigure = true

        ImageCache.default.memoryStorage.config.expiration = .days(7)
        ImageCache.default.diskStorage.config.expiration = .days(7)
    }
}

private struct TimelineBoardView: View {
    let orderedDays: [String]
    let timeline: TimelineDayMap
    let focusRestoreToken: Int
    let lastFocusedEntryID: Binding<String?>
    let pendingRestoreEntryID: Binding<String?>
    let openAnimeDetail: (Int) -> Void

    @Namespace private var timelineFocusScope
    @FocusState private var focusedEntryID: String?
    @State private var didScrollToInitialPosition = false
    @State private var currentTime = Date()
    private let currentTimeTicker = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollViewReader { scrollProxy in
            GeometryReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 28) {
                        ForEach(orderedDays, id: \.self) { day in
                            TimelineDayColumnView(
                                dayKey: day,
                                entries: timeline[day, default: []],
                                isToday: day == TimelineBoardFormatter.todayKey,
                                availableHeight: max(proxy.size.height - 36, 320),
                                shouldPreferInitialFocus: day == TimelineBoardFormatter.todayKey,
                                currentTime: currentTime,
                                focusedEntryID: $focusedEntryID,
                                focusScope: timelineFocusScope,
                                openAnimeDetail: openAnimeDetail
                            )
                            .id(day)
                        }
                    }
                    .frame(height: proxy.size.height - 36, alignment: .top)
                    .padding(.horizontal, 48)
                    .padding(.top, 36)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .focusScope(timelineFocusScope)
                .task {
                    guard !didScrollToInitialPosition else { return }
                    didScrollToInitialPosition = true
                    await focusInitialEntry(using: scrollProxy)
                }
                .onReceive(currentTimeTicker) { value in
                    currentTime = value
                }
                .onChange(of: focusedEntryID) { _, newValue in
                    guard let newValue else { return }
                    lastFocusedEntryID.wrappedValue = newValue
                }
                .onChange(of: focusRestoreToken) { _, _ in
                    Task { @MainActor in
                        await restoreFocusedEntry(using: scrollProxy)
                    }
                }
            }
        }
    }

    private func focusInitialEntry(using scrollProxy: ScrollViewProxy) async {
        guard let targetDay = orderedDays.first(where: { $0 == TimelineBoardFormatter.todayKey }) else {
            return
        }

        let todayIndex = orderedDays.firstIndex(of: targetDay) ?? 0
        let leadingIndex = max(todayIndex - 1, 0)
        let leadingDay = orderedDays[leadingIndex]

        withAnimation(.easeInOut(duration: 0.35)) {
            scrollProxy.scrollTo(leadingDay, anchor: .leading)
        }

        try? await Task.sleep(for: .milliseconds(350))

        guard let targetEntryID = preferredEntryID(for: targetDay) else { return }
        focusedEntryID = nil
        await Task.yield()
        focusedEntryID = targetEntryID
        lastFocusedEntryID.wrappedValue = targetEntryID
    }

    private func restoreFocusedEntry(using scrollProxy: ScrollViewProxy) async {
        await Task.yield()
        if let rememberedEntryID = pendingRestoreEntryID.wrappedValue,
           let dayKey = orderedDays.first(where: { day in
               timeline[day, default: []].contains(where: { $0.id == rememberedEntryID })
           }) {
            withAnimation(.easeInOut(duration: 0.3)) {
                scrollProxy.scrollTo(dayKey, anchor: .center)
            }
            try? await Task.sleep(for: .milliseconds(250))
            focusedEntryID = nil
            await Task.yield()
            focusedEntryID = rememberedEntryID
            lastFocusedEntryID.wrappedValue = rememberedEntryID
            pendingRestoreEntryID.wrappedValue = nil
            return
        }

        if let rememberedEntryID = lastFocusedEntryID.wrappedValue,
           let dayKey = orderedDays.first(where: { day in
               timeline[day, default: []].contains(where: { $0.id == rememberedEntryID })
           }) {
            withAnimation(.easeInOut(duration: 0.3)) {
                scrollProxy.scrollTo(dayKey, anchor: .center)
            }
            try? await Task.sleep(for: .milliseconds(250))
            focusedEntryID = nil
            await Task.yield()
            focusedEntryID = rememberedEntryID
            lastFocusedEntryID.wrappedValue = rememberedEntryID
            return
        }
        if let focusedEntryID,
           let dayKey = orderedDays.first(where: { day in
               timeline[day, default: []].contains(where: { $0.id == focusedEntryID })
        }) {
            withAnimation(.easeInOut(duration: 0.3)) {
                scrollProxy.scrollTo(dayKey, anchor: .center)
            }
            try? await Task.sleep(for: .milliseconds(250))
            self.focusedEntryID = nil
            await Task.yield()
            self.focusedEntryID = focusedEntryID
            lastFocusedEntryID.wrappedValue = focusedEntryID
            return
        }

        await focusInitialEntry(using: scrollProxy)
    }

    private func preferredEntryID(for dayKey: String) -> String? {
        let entries = timeline[dayKey, default: []]
        guard !entries.isEmpty else { return nil }

        let nowTimestamp = Int(currentTime.timeIntervalSince1970)
        if let nextIndex = entries.firstIndex(where: { $0.airingTimestamp > nowTimestamp }) {
            let targetIndex = max(nextIndex - 1, 0)
            return entries[targetIndex].id
        }

        return entries.last?.id
    }
}

private struct TimelineDayColumnView: View {
    let dayKey: String
    let entries: [TimelineEpisodeEntry]
    let isToday: Bool
    let availableHeight: CGFloat
    let shouldPreferInitialFocus: Bool
    let currentTime: Date
    let focusedEntryID: FocusState<String?>.Binding
    let focusScope: Namespace.ID
    let openAnimeDetail: (Int) -> Void

    private let headerHeight: CGFloat = 72
    @State private var didScrollToPreferredEntry = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(TimelineBoardFormatter.monthDayText(for: dayKey))
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(.white)

                if isToday {
                    Text("Today")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.cyan.opacity(0.9))
                } else {
                    Text(TimelineBoardFormatter.weekdayText(for: dayKey))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: headerHeight, alignment: .topLeading)
            .padding(.bottom, 18)

            ScrollViewReader { scrollProxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            if shouldShowSplitter(before: index) {
                                TimelineNowSplitter(currentTime: currentTime)
                            }

                            TimelineEpisodeCard(
                                entry: entry,
                                shouldPreferFocus: shouldPreferInitialFocus && preferredFocusIndex == index,
                                focusedEntryID: focusedEntryID,
                                focusScope: focusScope,
                                openAnimeDetail: openAnimeDetail
                            )
                            .id(entry.id)
                        }

                        if shouldShowSplitterAtEnd {
                            TimelineNowSplitter(currentTime: currentTime)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(height: max(availableHeight - headerHeight, 220))
                .task {
                    guard shouldPreferInitialFocus,
                          !didScrollToPreferredEntry,
                          let preferredEntryID else { return }

                    didScrollToPreferredEntry = true
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo(preferredEntryID, anchor: .center)
                        }
                        focusedEntryID.wrappedValue = preferredEntryID
                    }
                }
                .onChange(of: focusedEntryID.wrappedValue) { _, newValue in
                    guard let newValue,
                          entries.contains(where: { $0.id == newValue }) else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            scrollProxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 420, height: availableHeight, alignment: .topLeading)
    }

    private var splitterInsertionIndex: Int? {
        guard isToday else { return nil }
        let nowTimestamp = Int(currentTime.timeIntervalSince1970)

        for (index, entry) in entries.enumerated() where entry.airingTimestamp > nowTimestamp {
            return index
        }
        return nil
    }

    private var preferredFocusIndex: Int {
        if let splitterInsertionIndex {
            return max(splitterInsertionIndex - 1, 0)
        }
        return max(entries.count - 1, 0)
    }

    private var preferredEntryID: String? {
        guard entries.indices.contains(preferredFocusIndex) else { return nil }
        return entries[preferredFocusIndex].id
    }

    private var shouldShowSplitterAtEnd: Bool {
        isToday && !entries.isEmpty && splitterInsertionIndex == nil
    }

    private func shouldShowSplitter(before index: Int) -> Bool {
        guard let splitterInsertionIndex else { return false }
        return index == splitterInsertionIndex
    }
}

private struct TimelineEpisodeCard: View {
    let entry: TimelineEpisodeEntry
    let shouldPreferFocus: Bool
    let focusedEntryID: FocusState<String?>.Binding
    let focusScope: Namespace.ID
    let openAnimeDetail: (Int) -> Void

    var body: some View {
        Spacer(minLength: 10)
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Text(displayTitle)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)


                    Text(displayTime)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(timeColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(timeBackground, in: Capsule())
                }

                Text(episodeLine)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(2)
            }
            .padding(.leading, 120)
            .padding(.top, 13)
            .padding(.trailing, 18)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1.2)
            )

            TimelinePosterButton(
                imageURL: entry.coverImageURL,
                shouldPreferFocus: shouldPreferFocus,
                focusID: entry.id,
                focusedEntryID: focusedEntryID,
                focusScope: focusScope,
                onOpen: {
                    if let bangumiID = entry.bangumiID.flatMap(Int.init) {
                        openAnimeDetail(bangumiID)
                    }
                }
            )
            .padding(.leading, 18)
            .padding(.top, 13)
            .zIndex(1)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, -10)
//        .offset(y: -10)
    }

    private var displayTitle: String {
        let cn = entry.subjectTitleCN?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cn.isEmpty ? entry.subjectTitle : cn
    }

    private var displayEpisodeTitle: String {
        let cn = entry.episodeNameCN?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cn.isEmpty { return cn }

        let original = entry.episodeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return original
    }

    private var episodeLine: String {
        let sortValue = TimelineBoardFormatter.episodeText(for: entry.episodeSort)
        let episodeTitle = displayEpisodeTitle
        if episodeTitle.isEmpty {
            return "第 \(sortValue) 集"
        }
        return "第 \(sortValue) 集 \(episodeTitle)"
    }

    private var displayTime: String {
        TimelineBoardFormatter.timeText(for: entry.airingTimestamp)
    }

    private var timeColor: Color {
        entry.airingTimestamp == .max ? .white.opacity(0.7) : .cyan.opacity(0.95)
    }

    private var timeBackground: Color {
        entry.airingTimestamp == .max ? .white.opacity(0.08) : .cyan.opacity(0.18)
    }
    private var cardBackground: LinearGradient {
        return LinearGradient(
            colors: [
                Color.white.opacity(0.1),
                Color.white.opacity(0.04)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct TimelinePosterButton: View {
    let imageURL: String?
    let shouldPreferFocus: Bool
    let focusID: String
    let focusedEntryID: FocusState<String?>.Binding
    let focusScope: Namespace.ID
    let onOpen: () -> Void

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: {
            focusedEntryID.wrappedValue = focusID
            onOpen()
        }) {
            KFImage(URL(string: imageURL ?? ""))
                .placeholder {
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 86, height: 122)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.card)
        .focused(focusedEntryID, equals: focusID)
        .prefersDefaultFocus(shouldPreferFocus, in: focusScope)
        .offset(y: isFocused ? 12 : 0)
        .zIndex(isFocused ? 2 : 0)
        .animation(.easeInOut(duration: 0.18), value: isFocused)
        .onChange(of: isFocused) { _, newValue in
            if newValue {
                focusedEntryID.wrappedValue = focusID
            }
        }
    }
}

private struct TimelineNowSplitter: View {
    let currentTime: Date

    var body: some View {
        HStack(spacing: 12) {
            Capsule()
                .fill(Color.cyan.opacity(0.85))
                .frame(height: 3)

            Text(TimelineBoardFormatter.currentTimeText(for: currentTime))
                .font(.caption.weight(.heavy))
                .foregroundStyle(.cyan.opacity(0.95))

            Capsule()
                .fill(Color.cyan.opacity(0.85))
                .frame(height: 3)
        }
        .padding(.vertical, 6)
    }
}

private enum TimelineBoardFormatter {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "M/d"
        return formatter
    }()

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let weekdaySymbols = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    static var todayKey: String {
        key(for: Date())
    }

    static func monthDayText(for key: String) -> String {
        guard let date = date(from: key) else { return key }
        return monthDayFormatter.string(from: date)
    }

    static func weekdayText(for key: String) -> String {
        guard let date = date(from: key) else { return "" }

        let weekdayIndex = calendar.component(.weekday, from: date) - 1
        let weekday = weekdaySymbols.indices.contains(weekdayIndex) ? weekdaySymbols[weekdayIndex] : ""
        guard !weekday.isEmpty else { return "" }

        let today = Date()
        let targetWeekStart = startOfWeek(for: date)
        let todayWeekStart = startOfWeek(for: today)
        let dayOffset = calendar.dateComponents([.day], from: todayWeekStart, to: targetWeekStart).day ?? 0

        if dayOffset <= -7 {
            return "上\(weekday)"
        }
        if dayOffset >= 7 {
            return "下\(weekday)"
        }
        return weekday
    }

    static func timeText(for timestamp: Int) -> String {
        guard timestamp != .max else { return "unknown" }
        return timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    static func currentTimeText() -> String {
        timeFormatter.string(from: Date())
    }

    static func currentTimeText(for date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func episodeText(for sort: Double?) -> String {
        guard let sort else { return "?" }
        if abs(sort.rounded() - sort) < 0.0001 {
            return String(Int(sort.rounded()))
        }
        return String(format: "%.1f", sort)
    }

    static func key(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func date(from key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }

    private static func startOfWeek(for date: Date) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }
}

#Preview("Timeline Board") {
    @Previewable @State var lastFocusedEntryID: String?
    @Previewable @State var pendingRestoreEntryID: String?
    let calendar = TimelineBoardFormatter.calendar
    let now = Date()
    let todayKey = TimelineBoardFormatter.key(for: now)
    let yesterdayKey = TimelineBoardFormatter.key(for: calendar.date(byAdding: .day, value: -1, to: now) ?? now)
    let tomorrowKey = TimelineBoardFormatter.key(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
    let laterToday = Int((calendar.date(byAdding: .hour, value: 2, to: now) ?? now).timeIntervalSince1970)
    let tonight = Int((calendar.date(byAdding: .hour, value: 5, to: now) ?? now).timeIntervalSince1970)

    let sampleTimeline: TimelineDayMap = [
        yesterdayKey: [
            TimelineEpisodeEntry(
                dateKey: yesterdayKey,
                airingTimestamp: Int((calendar.date(byAdding: .hour, value: -20, to: now) ?? now).timeIntervalSince1970),
                anilistID: 101,
                bangumiID: "621358",
                subjectTitle: "魔物喰らいの冒険者～俺だけ魔物を喰らって強くなる～",
                subjectTitleCN: "吞噬魔物的冒险者",
                episodeID: 9001,
                episodeSort: 1,
                episodeName: "瘴気漁り",
                episodeNameCN: "",
                coverImageURL: "https://lain.bgm.tv/pic/cover/l/8f/47/621358_hVvMr.jpg",
                isAniListMissing: false
            )
        ],
        todayKey: [
            TimelineEpisodeEntry(
                dateKey: todayKey,
                airingTimestamp: Int((calendar.date(byAdding: .hour, value: -1, to: now) ?? now).timeIntervalSince1970),
                anilistID: 201,
                bangumiID: "620001",
                subjectTitle: "勇者之扉",
                subjectTitleCN: "勇者之扉",
                episodeID: 9101,
                episodeSort: 13,
                episodeName: "勇者的觉醒",
                episodeNameCN: "",
                coverImageURL: "https://lain.bgm.tv/pic/cover/l/0b/52/620001_example.jpg",
                isAniListMissing: false
            ),
            TimelineEpisodeEntry(
                dateKey: todayKey,
                airingTimestamp: laterToday,
                anilistID: 202,
                bangumiID: "620002",
                subjectTitle: "摩绪",
                subjectTitleCN: "",
                episodeID: 9102,
                episodeSort: 2,
                episodeName: "集结魔链女",
                episodeNameCN: "",
                coverImageURL: "https://lain.bgm.tv/pic/cover/l/1a/11/620002_example.jpg",
                isAniListMissing: false
            ),
            TimelineEpisodeEntry(
                dateKey: todayKey,
                airingTimestamp: tonight,
                anilistID: 203,
                bangumiID: "620003",
                subjectTitle: "主播女孩重度依赖",
                subjectTitleCN: "主播女孩重度依赖",
                episodeID: 9103,
                episodeSort: 2,
                episodeName: "Just the Two of Us",
                episodeNameCN: "",
                coverImageURL: "https://lain.bgm.tv/pic/cover/l/2b/22/620003_example.jpg",
                isAniListMissing: false
            )
        ],
        tomorrowKey: [
            TimelineEpisodeEntry(
                dateKey: tomorrowKey,
                airingTimestamp: Int.max,
                anilistID: nil,
                bangumiID: "620004",
                subjectTitle: "边缘大人的白给是恶魔级",
                subjectTitleCN: "边缘大人的白给是恶魔级",
                episodeID: 9104,
                episodeSort: 2,
                episodeName: "アニきちゃった",
                episodeNameCN: "",
                coverImageURL: "https://lain.bgm.tv/pic/cover/l/3c/33/620004_example.jpg",
                isAniListMissing: true
            )
        ]
    ]

    TimelineBoardView(
        orderedDays: [yesterdayKey, todayKey, tomorrowKey],
        timeline: sampleTimeline,
        focusRestoreToken: 0,
        lastFocusedEntryID: $lastFocusedEntryID,
        pendingRestoreEntryID: $pendingRestoreEntryID,
        openAnimeDetail: { _ in }
    )
}
