import SwiftUI
import WidgetKit

struct Snapshot: Decodable {
    struct Balance: Decodable, Identifiable { let id: Int; let name: String; let balance: Double }
    struct Call: Decodable, Identifiable {
        let id: Int; let vendor: String; let inputTokens: Int; let outputTokens: Int
        let cacheHitRate: Double?; let estimatedCost: Double?
    }
    let generatedAt: String
    let balances: [Balance]
    let recentCalls: [Call]
}
struct Entry: TimelineEntry { let date: Date; let snapshot: Snapshot? }
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(read()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [read()], policy: .after(.now.addingTimeInterval(1800))))
    }
    func read() -> Entry {
        let text = UserDefaults(suiteName: "group.com.zzxan.metapim")?.string(forKey: "metapim.snapshot")
        let snapshot = text?.data(using: .utf8).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        return Entry(date: .now, snapshot: snapshot)
    }
}
struct Summary: View {
    let entry: Entry
    @Environment(\.widgetFamily) var family
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("MetapiM").font(.headline)
            if let snapshot = entry.snapshot {
                Text("供应商余额").font(.caption).foregroundStyle(.secondary)
                ForEach(snapshot.balances.prefix(family == .systemLarge ? 4 : 2)) { b in
                    HStack { Text(b.name).lineLimit(1); Spacer(); Text(String(format: "$%.2f", b.balance)) }.font(.caption)
                }
                Divider()
                ForEach(snapshot.recentCalls.prefix(family == .systemLarge ? 4 : 1)) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack { Text(c.vendor).lineLimit(1); Spacer(); Text(c.estimatedCost.map { String(format: "$%.6f", $0) } ?? "-") }
                        Text("入 \(c.inputTokens) / 出 \(c.outputTokens) · 缓存 \(c.cacheHitRate.map { String(format: "%.1f%%", $0 * 100) } ?? "-")").lineLimit(1).minimumScaleFactor(0.7)
                    }.font(.caption2)
                }
                Spacer(minLength: 0)
                Text("快照：\(snapshot.generatedAt)").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            } else { Text("打开 MetapiM 登录并刷新").font(.caption); Spacer() }
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
