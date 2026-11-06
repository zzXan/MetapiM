import SwiftUI
import WidgetKit
import AppIntents

struct RefreshMetapiWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "刷新 MetapiM"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        guard let group = SharedGroup.resolve(),
              let credentials = WidgetSession.read(group: group) else {
            throw NSError(domain: "MetapiM.Widget", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "无法读取共享连接，请在 MetapiM 中检查共享权限"])
        }
        let snapshot = try await WidgetNetwork.fetch(credentials)
        guard let current = WidgetSession.read(group: group),
              current.server == credentials.server, current.token == credentials.token else {
            return .result()
        }
        let data = try JSONEncoder().encode(snapshot)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        UserDefaults(suiteName: group)?.set(text, forKey: "metapim.snapshot")
        WidgetCenter.shared.reloadTimelines(ofKind: "MetapiMWidget")
        return .result()
    }
}

struct Snapshot: Codable {
    struct Balance: Codable, Identifiable { let id: Int; let name: String; let balance: Double }
    struct Call: Codable, Identifiable {
        let id: Int; let vendor: String; let inputTokens: Int; let outputTokens: Int
        let cacheHitRate: Double?; let estimatedCost: Double?
    }
    let generatedAt: String
    let balances: [Balance]
    let recentCalls: [Call]
}
struct Entry: TimelineEntry { let date: Date; let snapshot: Snapshot?; var issue: String? = nil }
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(read()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        Task {
            var entry = read()
            if let group = SharedGroup.resolve(), let credentials = WidgetSession.read(group: group) {
                do {
                    let snapshot = try await WidgetNetwork.fetch(credentials)
                    // Discard a response if logout or a connection change happened in flight.
                    if let current = WidgetSession.read(group: group),
                       current.server == credentials.server && current.token == credentials.token {
                        if let data = try? JSONEncoder().encode(snapshot), let text = String(data: data, encoding: .utf8) {
                            UserDefaults(suiteName: group)?.set(text, forKey: "metapim.snapshot")
                        }
                        entry = Entry(date: .now, snapshot: snapshot)
                    } else { entry = Entry(date: .now, snapshot: nil, issue: "已登出") }
                } catch {
                    entry.issue = "刷新失败，保留上次快照"
                }
            }
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(1800))))
        }
    }
    func read() -> Entry {
        guard let group = SharedGroup.resolve() else {
            return Entry(date: .now, snapshot: nil, issue: "App Group 不可用，请检查重签共享权限")
        }
        guard let text = UserDefaults(suiteName: group)?.string(forKey: "metapim.snapshot"),
              let data = text.data(using: .utf8) else {
            return Entry(date: .now, snapshot: nil, issue: "没有共享快照，请在 App 刷新并查看错误提示")
        }
        do {
            return Entry(date: .now, snapshot: try JSONDecoder().decode(Snapshot.self, from: data))
        } catch {
            return Entry(date: .now, snapshot: nil, issue: "共享快照解析失败，请更新 App 后重新刷新")
        }
    }
}
struct Summary: View {
    let entry: Entry
    @Environment(\.widgetFamily) var family
    private func localRefreshTime(_ value: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = parser.date(from: value)
        if date == nil {
            parser.formatOptions = [.withInternetDateTime]
            date = parser.date(from: value)
        }
        guard let date = date else { return "-" }
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("MetapiM").font(.headline)
                Spacer()
                Button(intent: RefreshMetapiWidgetIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("刷新余额和调用记录")
            }
            if let snapshot = entry.snapshot {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(snapshot.balances.prefix(family == .systemLarge ? 8 : 3)) { b in
                            HStack { Text(b.name).lineLimit(1); Spacer(minLength: 2); Text(String(format: "$%.2f", b.balance)) }.font(.caption)
                        }
                        if snapshot.balances.isEmpty { Text("暂无余额").font(.caption) }
                    }.frame(maxWidth: .infinity, alignment: .topLeading)
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(snapshot.recentCalls.prefix(family == .systemLarge ? 6 : 2)) { c in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack { Text(c.vendor).lineLimit(1); Spacer(minLength: 2); Text(c.estimatedCost.map { String(format: "$%.6f", $0) } ?? "-") }
                                Text("\(c.inputTokens) / \(c.outputTokens) · \(c.cacheHitRate.map { String(format: "%.1f%%", $0 * 100) } ?? "-")")
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }.font(.caption2)
                        }
                        if snapshot.recentCalls.isEmpty { Text("暂无调用").font(.caption) }
                    }.frame(maxWidth: .infinity, alignment: .topLeading)
                }
                Spacer(minLength: 0)
                Text("刷新：\(localRefreshTime(snapshot.generatedAt))").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            } else { Text(entry.issue ?? "打开 MetapiM 登录并刷新").font(.caption); Spacer() }
        }.containerBackground(.background, for: .widget)
    }
}
@main
struct MetapiMWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MetapiMWidget", provider: Provider()) { Summary(entry: $0) }
            .configurationDisplayName("MetapiM")
            .description("供应商余额排名、最新调用及费用")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}
