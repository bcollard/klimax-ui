import SwiftUI
import Charts

/// Live CPU and memory graphs for the klimax VM. Polled over SSH every 5 s
/// (see AppModel.startVMPollingIfRunning).
struct VMChartsView: View {
    @Bindable var model: AppModel
    @Environment(AppSettings.self) private var settings
    /// Hover state shared by both charts so the rule + tooltip stay in sync.
    @State private var hoverTime: Date?

    /// Poll cadence in whole seconds, for the resolution / window labels.
    private var stepSeconds: Int { max(1, Int(settings.vmPollSeconds)) }

    private var samples: [VMSample] { model.vmHistory.samples }
    private var hoveredSample: VMSample? {
        guard let t = hoverTime, !samples.isEmpty else { return nil }
        return samples.min { abs($0.timestamp.timeIntervalSince(t)) < abs($1.timestamp.timeIntervalSince(t)) }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                header
                if samples.count < 2 {
                    Text("Waiting for the first interval… (poll every \(stepSeconds)s)")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    cpuChart
                    memChart
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("VM resources")
                .font(.headline)
            Text("\(stepSeconds)s resolution · last \(model.vmHistory.capacity * stepSeconds / 60) min")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let latest = samples.last {
                HStack(spacing: 12) {
                    if let cpu = latest.cpuPercent {
                        pill("CPU", String(format: "%.0f%%", cpu))
                    }
                    pill("Mem", String(format: "%.1f / %.1f GiB",
                                       latest.memUsedMiB / 1024,
                                       latest.memTotalMiB / 1024))
                }
            }
        }
    }

    private var cpuChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CPU (%)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Chart {
                ForEach(samples.filter { $0.cpuPercent != nil }) { s in
                    let value = s.cpuPercent ?? 0
                    LineMark(
                        x: .value("Time", s.timestamp),
                        y: .value("CPU %", value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.orange)
                    AreaMark(
                        x: .value("Time", s.timestamp),
                        y: .value("CPU %", value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.linearGradient(
                        colors: [.orange.opacity(0.4), .orange.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                }
                if let hovered = hoveredSample, let cpu = hovered.cpuPercent {
                    RuleMark(x: .value("Time", hovered.timestamp))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                    PointMark(
                        x: .value("Time", hovered.timestamp),
                        y: .value("CPU %", cpu)
                    )
                    .foregroundStyle(.orange)
                    .symbolSize(80)
                }
            }
            .chartYScale(domain: 0...100)
            .frame(height: 140)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 25, 50, 75, 100])
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
                    yValue: hoveredSample?.cpuPercent,
                    line: hoveredSample?.cpuPercent.map { String(format: "CPU %.0f%%", $0) }
                )
            }
        }
    }

    private var memChart: some View {
        let totalMiB = samples.last?.memTotalMiB ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            Text("Memory used (GiB)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Chart {
                ForEach(samples) { s in
                    LineMark(
                        x: .value("Time", s.timestamp),
                        y: .value("Used (GiB)", s.memUsedMiB / 1024)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.cyan)
                    AreaMark(
                        x: .value("Time", s.timestamp),
                        y: .value("Used (GiB)", s.memUsedMiB / 1024)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.linearGradient(
                        colors: [.cyan.opacity(0.4), .cyan.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                }
                if let hovered = hoveredSample {
                    RuleMark(x: .value("Time", hovered.timestamp))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                    PointMark(
                        x: .value("Time", hovered.timestamp),
                        y: .value("Used (GiB)", hovered.memUsedMiB / 1024)
                    )
                    .foregroundStyle(.cyan)
                    .symbolSize(80)
                }
            }
            .chartYScale(domain: 0...(totalMiB / 1024))
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
                    yValue: hoveredSample.map { $0.memUsedMiB / 1024 },
                    line: hoveredSample.map { String(format: "%.2f GiB used", $0.memUsedMiB / 1024) }
                )
            }
        }
    }

    /// Captures continuous-hover gestures and (when something is hovered) draws
    /// a floating tooltip positioned just above the data point on the line.
    @ViewBuilder
    private func hoverLayer(proxy: ChartProxy, yValue: Double?, line: String?) -> some View {
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
                tooltip(time: s.timestamp, line: line)
                    .fixedSize()
                    .position(
                        x: min(max(xAbs, rect.minX + 50), rect.maxX - 50),
                        y: max(yAbs - 28, rect.minY + 18)
                    )
                    .allowsHitTesting(false)
            }
        }
    }

    private func tooltip(time: Date, line: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(time, format: .dateTime.hour().minute().second())
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(line)
                .font(.caption.bold().monospacedDigit())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.thinMaterial)
                .shadow(radius: 2)
        )
    }

    private func pill(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Text(value).bold()
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
    }
}
