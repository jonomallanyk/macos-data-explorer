import AppKit
import SwiftUI
import DataExplorerCore

extension StorageCategory {
    var color: Color {
        switch self {
        case .apps: return .blue
        case .personalFiles: return .indigo
        case .mediaLibraries: return .pink
        case .cloudFiles: return .cyan
        case .mailAndMessages: return .teal
        case .deviceBackups: return .mint
        case .developer: return .orange
        case .virtualMachines: return .purple
        case .caches: return .yellow
        case .logs: return .brown
        case .appData: return .green
        case .systemManaged: return Color(red: 0.55, green: 0.57, blue: 0.62)
        case .trash: return .red
        case .other: return Color(red: 0.72, green: 0.72, blue: 0.74)
        }
    }

    var symbolName: String {
        switch self {
        case .apps: return "app.badge"
        case .personalFiles: return "doc.on.doc"
        case .mediaLibraries: return "photo.on.rectangle"
        case .cloudFiles: return "icloud"
        case .mailAndMessages: return "envelope"
        case .deviceBackups: return "iphone"
        case .developer: return "hammer"
        case .virtualMachines: return "shippingbox"
        case .caches: return "bolt.horizontal"
        case .logs: return "list.bullet.rectangle"
        case .appData: return "square.stack.3d.up"
        case .systemManaged: return "gearshape.2"
        case .trash: return "trash"
        case .other: return "questionmark.folder"
        }
    }
}

extension SafetyLevel {
    var color: Color {
        switch self {
        case .safe: return .green
        case .review: return .blue
        case .caution: return .orange
        case .protected: return .secondary
        }
    }
}

func formatBytes(_ bytes: Int64) -> String {
    ByteFormatter.string(bytes)
}

/// A coloured pill describing how safe something is to delete.
struct SafetyBadge: View {
    let level: SafetyLevel
    var compact = false

    var body: some View {
        Group {
            if compact {
                Image(systemName: level.symbolName)
                    .foregroundStyle(level.color)
            } else {
                Label(level.title, systemImage: level.symbolName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(level.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(level.color.opacity(0.12), in: Capsule())
            }
        }
        .help(level.explanation)
    }
}

/// A thin horizontal bar showing a share of a total.
struct SizeBar: View {
    let fraction: Double
    var color: Color = .accentColor

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(color)
                    .frame(width: max(2, proxy.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 6)
    }
}

struct CapacitySegment: Identifiable {
    let id: String
    let title: String
    let bytes: Int64
    let color: Color
    var detail: String = ""
}

/// The big stacked bar at the top of the overview.
struct CapacityBar: View {
    let segments: [CapacitySegment]
    let total: Int64

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 1) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(segment.color.gradient)
                        .frame(width: width(of: segment, in: proxy.size.width))
                        .help("\(segment.title): \(formatBytes(segment.bytes))")
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 22)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func width(of segment: CapacitySegment, in available: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        let usable = available - CGFloat(max(0, segments.count - 1))
        return max(1, usable * CGFloat(Double(segment.bytes) / Double(total)))
    }
}

/// A checkbox that can also show a "some selected" state.
struct CheckboxButton: View {
    let state: CheckState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(state == .unchecked ? Color.secondary : Color.accentColor)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state == .unavailable)
        .opacity(state == .unavailable ? 0.3 : 1)
        .help(state == .unavailable ? "Can't be deleted from Data Explorer" : "Add to the cleanup list")
    }

    private var symbol: String {
        switch state {
        case .checked: return "checkmark.square.fill"
        case .mixed: return "minus.square.fill"
        case .unchecked, .unavailable: return "square"
        }
    }
}

/// A rounded panel used throughout the app.
struct Card<Content: View>: View {
    var title: String?
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.title3.weight(.semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07)))
    }
}

/// Shown when there's nothing to display yet.
struct EmptyState<Actions: View>: View {
    let systemImage: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.title2.weight(.semibold))
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            actions
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Buttons for starting a scan, used by empty states.
struct ScanButtons: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Button {
                model.startScan(scope: .entireMac)
            } label: {
                Label("Scan Entire Mac", systemImage: "internaldrive")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                model.startScan(scope: .home)
            } label: {
                Label("Scan Home Folder", systemImage: "house")
            }
            .controlSize(.large)
        }
        .disabled(model.isScanning)
    }
}

/// A short labelled paragraph, e.g. "If you delete it: …".
struct LabeledText: View {
    let label: String
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }
            (Text(label + " ").fontWeight(.semibold) + Text(text))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }
}

/// Instructions for things that have to be cleaned up somewhere else.
struct ManualStepsBox: View {
    let steps: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 3) {
                Text("How to free this space").font(.callout.weight(.semibold))
                Text(steps)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

extension View {
    /// Monospaced digits for sizes, so columns line up.
    func sizeStyle() -> some View {
        self.monospacedDigit()
    }
}
