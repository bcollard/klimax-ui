import SwiftUI
import Charts

struct MetricsChartsView: View {
    @Bindable var model: AppModel
    @Environment(AppSettings.self) private var settings
    let cluster: KindCluster
    /// Hover state shared by both charts so the rule + tooltip stay in sync.
    @State private var hoverTime: Date?

    /// Poll cadence in whole seconds, for the resolution / window labels.
    private var stepSeconds: Int { max(1, Int(settings.metricsPollSeconds)) }
    /// Pod id ("namespace/name") hovered in the Top pods table — overlays the
    /// pod's history on both charts when set.
    @State private var hoveredPodID: String?

    private var history: MetricsHistory {
        model.metricsHistory[cluster.name] ?? MetricsHistory()
    }
    private var pods: [PodMetric] {
        model.latestPods[cluster.name] ?? []
    }
    private var error: String? {
        model.metricsError[cluster.name]
    }
    private var hoveredSample: ClusterMetricSample? {
        guard let t = hoverTime, !history.samples.isEmpty else { return nil }
        return history.samples.min {
            abs($0.timestamp.timeIntervalSince(t)) < abs($1.timestamp.timeIntervalSince(t))
        }
    }
    private var hoveredPodSamples: [PodMetric] {
        guard let id = hoveredPodID,
              let h = model.podHistory[cluster.name]?[id]
        else { return [] }
        return h.samples
    }
    /// The hovered pod's sample closest to `hoverTime`, if a chart hover is active.
    private var hoveredPodSampleAtCursor: PodMetric? {
        guard let t = hoverTime else { return nil }
        return hoveredPodSamples.min {
            abs($0.timestamp.timeIntervalSince(t)) < abs($1.timestamp.timeIntervalSince(t))
        }
    }
    /// Display name for the tooltip's pod row.
    private var hoveredPodName: String? {
        guard let id = hoveredPodID else { return nil }
        return id.split(separator: "/", maxSplits: 1).last.map(String.init) ?? id
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
                if history.samples.isEmpty {
                    Text("Waiting for the first sample… (poll every \(stepSeconds)s)")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    cpuChart
                    memChart
                }
                if !pods.isEmpty {
                    Divider()
                    topPodsTable
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Live metrics")
                .font(.headline)
            Text("metrics-server · \(stepSeconds)s resolution · last \(history.capacity * stepSeconds / 60) min")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let latest = history.samples.last {
                HStack(spacing: 12) {
                    pill("CPU", String(format: "%.0f m", latest.totalCPUMillicores))
                    pill("Mem", String(format: "%.0f MiB", latest.totalMemoryMiB))
                }
            }
        }
    }

    // MARK: - Charts

    private var cpuChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CPU (millicores)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Chart {
                ForEach(history.samples) { sample in
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("CPU (m)", sample.totalCPUMillicores),
                        series: .value("Series", "cluster")
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.blue)
                    AreaMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("CPU (m)", sample.totalCPUMillicores)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.linearGradient(
                        colors: [.blue.opacity(0.4), .blue.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                }
                ForEach(hoveredPodSamples) { sample in
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("CPU (m)", sample.cpuMillicores),
                        series: .value("Series", "pod")
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.orange)
                }
                if let hovered = hoveredSample {
                    RuleMark(x: .value("Time", hovered.timestamp))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                    PointMark(
                        x: .value("Time", hovered.timestamp),
                        y: .value("CPU (m)", hovered.totalCPUMillicores)
                    )
                    .foregroundStyle(.blue)
                    .symbolSize(80)
                    if let podSample = hoveredPodSampleAtCursor {
                        PointMark(
                            x: .value("Time", podSample.timestamp),
                            y: .value("CPU (m)", podSample.cpuMillicores)
                        )
                        .foregroundStyle(.orange)
                        .symbolSize(80)
                    }
                }
            }
            .frame(height: 140)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
            .chartOverlay { proxy in
                hoverLayer(
                    proxy: proxy,
                    yValue: hoveredSample?.totalCPUMillicores,
                    line: hoveredSample.map { String(format: "%.0f m", $0.totalCPUMillicores) },
                    podLine: hoveredPodSampleAtCursor
                        .map { String(format: "%.0f m", $0.cpuMillicores) }
                )
            }
        }
    }

    private var memChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Memory (MiB)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Chart {
                ForEach(history.samples) { sample in
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Mem (MiB)", sample.totalMemoryMiB),
                        series: .value("Series", "cluster")
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.green)
                    AreaMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Mem (MiB)", sample.totalMemoryMiB)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.linearGradient(
                        colors: [.green.opacity(0.4), .green.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                }
                ForEach(hoveredPodSamples) { sample in
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Mem (MiB)", sample.memoryMiB),
                        series: .value("Series", "pod")
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.orange)
                }
                if let hovered = hoveredSample {
                    RuleMark(x: .value("Time", hovered.timestamp))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                    PointMark(
                        x: .value("Time", hovered.timestamp),
                        y: .value("Mem (MiB)", hovered.totalMemoryMiB)
                    )
                    .foregroundStyle(.green)
                    .symbolSize(80)
                    if let podSample = hoveredPodSampleAtCursor {
                        PointMark(
                            x: .value("Time", podSample.timestamp),
                            y: .value("Mem (MiB)", podSample.memoryMiB)
                        )
                        .foregroundStyle(.orange)
                        .symbolSize(80)
                    }
                }
            }
            .frame(height: 140)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
            .chartOverlay { proxy in
                hoverLayer(
                    proxy: proxy,
                    yValue: hoveredSample?.totalMemoryMiB,
                    line: hoveredSample.map { String(format: "%.0f MiB", $0.totalMemoryMiB) },
                    podLine: hoveredPodSampleAtCursor
                        .map { String(format: "%.0f MiB", $0.memoryMiB) }
                )
            }
        }
    }

    @ViewBuilder
    private func hoverLayer(
        proxy: ChartProxy,
        yValue: Double?,
        line: String?,
        podLine: String?
    ) -> some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        guard let plot = proxy.plotFrame else { return }
                        let x = location.x - geo[plot].origin.x
                        if let date: Date = proxy.value(atX: x) {
                            hoverTime = date
                        }
                    case .ended:
                        hoverTime = nil
                    }
                }

            if let s = hoveredSample,
               let yValue,
               let line,
               let plot = proxy.plotFrame,
               let xRel = proxy.position(forX: s.timestamp),
               let yRel = proxy.position(forY: yValue)
            {
                let rect = geo[plot]
                let xAbs = rect.minX + xRel
                let yAbs = rect.minY + yRel
                tooltip(time: s.timestamp, line: line, podLine: podLine, podName: hoveredPodName)
                    .fixedSize()
                    .position(
                        x: min(max(xAbs, rect.minX + 50), rect.maxX - 50),
                        y: max(yAbs - 28, rect.minY + 18)
                    )
                    .allowsHitTesting(false)
            }
        }
    }

    private func tooltip(time: Date, line: String, podLine: String?, podName: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(time, format: .dateTime.hour().minute().second())
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Circle().fill(.blue).frame(width: 6, height: 6)
                Text(line)
                    .font(.caption.bold().monospacedDigit())
            }
            if let podLine, let podName {
                HStack(spacing: 6) {
                    Circle().fill(.orange).frame(width: 6, height: 6)
                    Text(podLine)
                        .font(.caption.bold().monospacedDigit())
                    Text(podName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.thinMaterial)
                .shadow(radius: 2)
        )
    }

    // MARK: - Top pods table

    private var topPodsTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Top pods")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            let topCPU = pods.sorted { $0.cpuMillicores > $1.cpuMillicores }.prefix(5)
            let topMem = pods.sorted { $0.memoryMiB > $1.memoryMiB }.prefix(5)
            HStack(alignment: .top, spacing: 16) {
                podColumn("by CPU", units: "m") { topCPU.map { ($0, $0.cpuMillicores) } }
                podColumn("by Memory", units: "MiB") { topMem.map { ($0, $0.memoryMiB) } }
            }
        }
    }

    private func podColumn(
        _ title: String,
        units: String,
        _ rows: () -> [(PodMetric, Double)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.tertiary)
            ForEach(rows(), id: \.0.id) { pod, value in
                let isHovered = hoveredPodID == pod.id
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(pod.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .font(.callout)
                        Text(pod.namespace)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(String(format: "%.0f \(units)", value))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovered ? Color.orange.opacity(0.15) : .clear)
                )
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering {
                        hoveredPodID = pod.id
                    } else if hoveredPodID == pod.id {
                        hoveredPodID = nil
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Bits

    private func pill(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Text(value).bold()
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Color.secondary.opacity(0.12))
        )
    }
}
