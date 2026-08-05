import SwiftUI

struct PresetItem: Identifiable {
    let id: UInt32
    let title: String
    let author: String?
    let category: String
    let filename: String

    // Preset filenames conventionally start with the author: "Author - Title.milk"
    static func parse(filename: String) -> (title: String, author: String?) {
        let stem = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let parts = stem.components(separatedBy: " - ")
        if parts.count >= 2 {
            return (parts.dropFirst().joined(separator: " - "), parts[0])
        }
        return (stem, nil)
    }
}

struct PresetSection: Identifiable {
    var id: String { name }
    let name: String
    let items: [PresetItem]
}

// Hand-picked subset shown by default; the full collection sits behind the toggle.
private let featuredFilenames: Set<String> = [
    "AdamFX to Geiss - Ghostly Infractions 5.milk",
    "EVET - Brainlocknrelease.milk",
    "amandio c - future engines.milk",
    "akish - churning.milk",
    "EVET - Aikea Galaxy.milk",
    "Flexi - alien complex 00.milk",
    "amandio c - pulse - sth.milk",
    "Adam Shark - the green line.milk",
    "Aderrasi - Graft (First Rate Heart).milk",
    "drugsincombat - reactive molecule v-05a.milk",
    "amandio c - dark side of the sun 1.milk",
    "amandio c - dark side of the sun 2.milk",
    "Aderrasi - Ashes Of Air (Remix).milk",
    "Aderrasi - Chromatic Abyss (Refined Abyss Mix).milk",
    "Aderrasi-spirits.milk",
]

struct PresetBrowserView: View {
    private let allSections: [PresetSection]
    private let featuredSections: [PresetSection]
    private let totalCount: Int
    private let onSelect: (UInt32) -> Void
    @AppStorage("showAllPresets") private var showAll = false
    @State private var search = ""

    init(presets: [PresetItem], onSelect: @escaping (UInt32) -> Void) {
        self.onSelect = onSelect
        totalCount = presets.count

        let grouped = Dictionary(grouping: presets, by: \.category)
        allSections = grouped.keys
            .sorted { a, b in
                if a == "Fishtank" || b == "Your Presets" { return b != "Fishtank" }
                if b == "Fishtank" || a == "Your Presets" { return false }
                return a.localizedStandardCompare(b) == .orderedAscending
            }
            .map { PresetSection(name: $0, items: grouped[$0] ?? []) }

        var featured: [PresetSection] = []
        if let custom = grouped["Fishtank"] {
            featured.append(PresetSection(name: "Fishtank", items: custom))
        }
        let picks = presets
            .filter { featuredFilenames.contains($0.filename) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        featured.append(PresetSection(name: "Featured", items: picks))
        if let user = grouped["Your Presets"] {
            featured.append(PresetSection(name: "Your Presets", items: user))
        }
        featuredSections = featured
    }

    private var visibleSections: [PresetSection] {
        let base = showAll ? allSections : featuredSections
        guard !search.isEmpty else { return base }
        return base.compactMap { section in
            let items = section.items.filter {
                $0.title.localizedCaseInsensitiveContains(search)
                    || ($0.author?.localizedCaseInsensitiveContains(search) ?? false)
            }
            return items.isEmpty ? nil : PresetSection(name: section.name, items: items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search presets", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(10)
            Divider()
            List(visibleSections) { section in
                Section(section.name) {
                    ForEach(section.items) { preset in
                        Button {
                            onSelect(preset.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(preset.title)
                                    .lineLimit(1)
                                if let author = preset.author {
                                    Text(author)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.inset)
            Divider()
            Toggle("Show all \(totalCount) presets", isOn: $showAll)
                .toggleStyle(.switch)
                .controlSize(.small)
                .padding(8)
        }
    }
}
