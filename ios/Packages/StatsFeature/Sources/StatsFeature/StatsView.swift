import DesignSystem
import SwiftUI

/// Profile → Stats (doc 10 §2, D-067): trophies first — league, next step, rank, record, trophy history, players to
/// beat — then push-ups as the secondary section (period picker, KPI tiles, charts, records, achievements).
public struct StatsView: View {
    @State private var model: StatsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let onFight: (() -> Void)?

    public init(model: StatsModel, onFight: (() -> Void)? = nil) {
        _model = State(initialValue: model)
        self.onFight = onFight
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingTokens.l) {
                ScreenTitle("Stats", token: TypographyTokens.displayM)
                if let battle = model.battle {
                    TrophySection(stats: battle, onFight: onFight)
                }
                SectionLabel("Push-ups")
                Picker("Period", selection: Binding(get: { model.period }, set: { p in Task { await model.select(p) } })) {
                    Text("Week").tag(StatsData.Period.week)
                    Text("Month").tag(StatsData.Period.month)
                    Text("Year").tag(StatsData.Period.year)
                    Text("All").tag(StatsData.Period.all)
                }
                .pickerStyle(.segmented)

                if let stats = model.stats {
                    content(stats)
                        .animation(reduceMotion ? nil : .easeOut(duration: MotionTokens.slowSeconds), value: stats)
                } else if model.failed {
                    InlineBanner("Stats couldn't load. Pull down to try again.", kind: .warning)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(.horizontal, SpacingTokens.l)
            .padding(.bottom, SpacingTokens.xl)
        }
        .refreshable { await model.refresh() }
        .arenaBackground(glow: ColorTokens.brandCyan, alignment: .top, offset: CGSize(width: 0, height: -260))
        .task {
            if model.battle == nil { await model.loadBattle() }
            if model.stats == nil { await model.load() }
            if model.achievements.isEmpty { await model.loadAchievements() }
        }
    }

    @ViewBuilder
    private func content(_ stats: StatsData) -> some View {
        LevelCard(level: stats.progress)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: SpacingTokens.m), GridItem(.flexible())], spacing: SpacingTokens.m) {
            StatTile(label: "Push-ups", value: "\(stats.kpis.reps)",
                     delta: StatsSeries.delta(stats.kpis.reps, stats.kpis.repsPrev))
            StatTile(label: "Best set", value: "\(stats.kpis.bestSet)",
                     delta: StatsSeries.delta(stats.kpis.bestSet, stats.kpis.bestSetPrev))
            StatTile(label: "Avg form", value: stats.kpis.avgQuality.map { "\($0)" } ?? "–",
                     delta: StatsSeries.delta(stats.kpis.avgQuality, stats.kpis.avgQualityPrev))
        }

        let bars = StatsSeries.bars(stats)
        ChartCard(title: "Daily push-ups") {
            DailyBarsChart(bars: bars, bucket: StatsSeries.bucket(from: stats.from, to: stats.to))
        }
        .accessibilityLabel(Text("Daily push-ups: \(stats.kpis.reps) in this period"))

        ChartCard(title: "All-time push-ups") {
            CumulativeChart(points: StatsSeries.cumulative(stats), milestones: StatsSeries.milestonesReached(stats))
        }


        let sets = StatsSeries.bestSets(stats)
        if !sets.isEmpty {
            ChartCard(title: "Best set", caption: "Stars mark new records") { BestSetChart(points: sets) }
        }

        ChartCard(title: "Activity") { HeatmapView(cells: StatsSeries.heatmap(stats, today: stats.to)) }

        RecordsCard(records: stats.records)

        NavigationLink {
            AchievementsView(model: model)
        } label: {
            HStack {
                Image(systemName: "rosette").accessibilityHidden(true)
                Text("Achievements")
                Spacer()
                Text(verbatim: "\(stats.achievements.unlocked) / \(stats.achievements.total)")
                    .foregroundStyle(Color(ColorTokens.textSecondary))
                Image(systemName: "chevron.right").accessibilityHidden(true)
            }
            .typography(TypographyTokens.titleS)
            .foregroundStyle(Color(ColorTokens.textPrimary))
            .padding(SpacingTokens.ml)
            .frame(minHeight: TouchTarget.minimum)
            .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.l))
        }
    }
}

struct LevelCard: View {
    let level: StatsData.Level

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Level \(level.level)")
                        .typography(TypographyTokens.displayM)
                        .foregroundStyle(Color(ColorTokens.textPrimary))
                    Spacer()
                    Text(verbatim: "\(level.xp) XP")
                        .typography(TypographyTokens.bodyS)
                        .foregroundStyle(Color(ColorTokens.brandVoltText))
                }
                GradientProgressBar(value: level.fraction, height: 10)
                Text("\(level.xpForNext - level.xpIntoLevel) XP to level \(level.level + 1)")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct StatTile: View {
    let label: LocalizedStringKey
    let value: String
    let delta: Int?
    var unit = ""

    var body: some View {
        Card(padding: SpacingTokens.m) {
            VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                Text(label)
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
                Text(verbatim: value)
                    .typography(TypographyTokens.stat)
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let delta, delta != 0 {
                    Label {
                        Text(verbatim: "\(abs(delta))\(unit)")
                    } icon: {
                        Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
                    }
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(delta > 0 ? Color(ColorTokens.stateSuccessText) : Color(ColorTokens.stateDanger))
                    .accessibilityLabel(Text(delta > 0 ? "up \(abs(delta)) from the previous period"
                                                       : "down \(abs(delta)) from the previous period"))
                } else {
                    Text(verbatim: " ").typography(TypographyTokens.caption).accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ChartCard<Content: View>: View {
    let title: LocalizedStringKey
    var caption: LocalizedStringKey?
    @ViewBuilder let content: () -> Content

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: SpacingTokens.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .typography(TypographyTokens.titleS)
                        .foregroundStyle(Color(ColorTokens.textPrimary))
                    if let caption {
                        Text(caption)
                            .typography(TypographyTokens.caption)
                            .foregroundStyle(Color(ColorTokens.textTertiary))
                    }
                }
                content()
            }
        }
    }
}

struct RecordsCard: View {
    let records: StatsData.Records

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: SpacingTokens.m) {
                Text("Personal records")
                    .typography(TypographyTokens.titleS)
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                Grid(alignment: .leading, horizontalSpacing: SpacingTokens.l, verticalSpacing: SpacingTokens.sm) {
                    GridRow { record("Best set", records.bestSet); record("Most in a day", records.maxDay) }
                    GridRow { record("Best streak", records.bestStreak); record("All time", records.repsAllTime) }
                }
            }
        }
    }

    private func record(_ label: LocalizedStringKey, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(value)")
                .typography(TypographyTokens.titleL)
                .foregroundStyle(Color(ColorTokens.textPrimary))
            Text(label)
                .typography(TypographyTokens.caption)
                .foregroundStyle(Color(ColorTokens.textTertiary))
        }
        .accessibilityElement(children: .combine)
    }
}
