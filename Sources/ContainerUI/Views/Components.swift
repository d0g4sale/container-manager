import SwiftUI
import Charts

// MARK: - Status pill

struct StatusPill: View {
    let running: Bool
    var label: String?

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(running ? Color.green : Color.secondary.opacity(0.6))
                .frame(width: 7, height: 7)
                .shadow(color: running ? .green.opacity(0.6) : .clear, radius: 3)
            Text(label ?? (running ? "Running" : "Stopped"))
                .font(.caption.weight(.medium))
                .foregroundStyle(running ? .primary : .secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(running ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12))
        )
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

// MARK: - Toast banner

struct ToastView: View {
    let toast: Toast

    private var color: Color {
        switch toast.kind {
        case .info: return .blue
        case .success: return .green
        case .error: return .red
        }
    }

    private var symbol: String {
        switch toast.kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(toast.message)
                .font(.callout)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(color.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .frame(maxWidth: 420)
        .padding(20)
    }
}

// MARK: - Key/value metadata row

struct MetaRow: View {
    let label: String
    let value: String
    var mono: Bool = false

    init(_ label: String, _ value: String, mono: Bool = false) {
        self.label = label
        self.value = value
        self.mono = mono
    }

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(mono ? .system(.callout, design: .monospaced) : .callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Section card

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Sparkline

/// A compact, axis-less area+line chart for showing a metric's recent trend.
struct Sparkline: View {
    let values: [Double]
    var tint: Color = .accentColor

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { index, value in
            AreaMark(x: .value("t", index), y: .value("v", value))
                .foregroundStyle(.linearGradient(
                    colors: [tint.opacity(0.35), tint.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("t", index), y: .value("v", value))
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: 0...(max(values.max() ?? 1, 0.000001) * 1.15))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

// MARK: - KPI tile

/// A headline metric card used on the dashboard and summary surfaces.
/// Pass `spark` to render a trend sparkline beneath the value, and `action`
/// to make the whole tile a navigation target.
struct KPITile: View {
    let title: String
    let value: String
    var caption: String?
    let symbol: String
    var tint: Color = .accentColor
    var spark: [Double]?
    var action: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        if let action {
            Button(action: action) { tile }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
        } else {
            tile
        }
    }

    private var tile: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .opacity(hovering ? 1 : 0)
                }
            }
            Text(value)
                .font(.title.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(caption ?? " ")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let spark {
                Group {
                    if spark.count >= 2 {
                        Sparkline(values: spark, tint: tint)
                    } else {
                        Color.clear
                    }
                }
                .frame(height: 30)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(hovering ? 0.5 : 0), lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

// MARK: - Summary bar

/// A thin top strip of inline metrics, divided from the content below.
/// Fill it with `MiniStat`s (and optional short `Divider()`s).
struct SummaryBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                content
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
        }
    }
}

// MARK: - Reclaim button

/// A compact button for pruning unused resources, sized to sit inside a
/// `SummaryBar` next to a "reclaimable" stat.
struct ReclaimButton: View {
    let bytes: Int64
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Reclaim", systemImage: "sparkles")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(.orange)
        .help("Reclaim \(Format.bytes(bytes)) of unused space")
    }
}

// MARK: - Mini stat (compact inline metric)

/// A small label·value pair for dense summary strips.
struct MiniStat: View {
    let value: String
    let label: String
    var tint: Color = .primary
    var dot: Color?

    var body: some View {
        HStack(spacing: 6) {
            if let dot {
                Circle().fill(dot).frame(width: 7, height: 7)
            }
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .fixedSize()
    }
}

// MARK: - Flow layout (wrapping chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth - spacing)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth - spacing)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Convenience wrapper to lay out a collection of items in a wrapping flow.
struct FlexWrap<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let data: Data
    let content: (Data.Element) -> Content

    init(_ data: Data, id: KeyPath<Data.Element, Data.Element> = \.self,
         @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
    }

    var body: some View {
        FlowLayout {
            ForEach(Array(data), id: \.self) { item in
                content(item)
            }
        }
    }
}

// MARK: - Sheet form field helpers

extension View {
    /// The standard bordered look for an editable field inside a sheet form:
    /// a visible rounded border with its (accessibility-only) label hidden so
    /// the field itself fills the row instead of being pushed aside by a label.
    func sheetField() -> some View {
        self.labelsHidden().textFieldStyle(.roundedBorder)
    }
}

/// A leading label paired with a bordered field that fills the remaining width,
/// so single fields read as clearly as the multi-field rows (ports, volumes).
struct LabeledField<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label).frame(width: 130, alignment: .leading)
            content
        }
    }
}

extension Binding where Value == String {
    /// A view of this binding that only ever stores digits — the setter strips
    /// any non-numeric characters as they are typed or pasted.
    var digitsOnly: Binding<String> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0.filter(\.isNumber) })
    }
}

extension Binding where Value: RangeReplaceableCollection, Value.Element: Identifiable {
    /// Removes the element with `id`, deferred to the next runloop tick.
    ///
    /// `ForEach($array)` binds each row's `TextField` by array position. Tapping
    /// a remove button moves focus off the field, which makes AppKit
    /// *synchronously* commit the edit through that positional binding. Mutating
    /// the array in the same turn lands that write-back on a now-stale index and
    /// traps with "Index out of range"; deferring lets the commit settle first.
    func removeDeferred(_ id: Value.Element.ID) {
        DispatchQueue.main.async {
            wrappedValue.removeAll { $0.id == id }
        }
    }
}

// MARK: - Toolbar icon button helper

struct CircleIconButton: View {
    let symbol: String
    let help: String
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(tint)
        .help(help)
    }
}
