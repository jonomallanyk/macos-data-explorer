import Foundation

/// A place on disk that Data Explorer can explain.
public struct KnownLocation: Identifiable, Sendable {
    public enum Cleanup: Sendable, Equatable {
        /// The matched file or folder can be deleted as a whole.
        case trashItem
        /// The folder itself must stay, but everything inside it can be deleted.
        case trashContents
        /// A general area: items inside can be deleted one at a time, never in bulk.
        case individually
        /// Shouldn't be deleted directly. The text explains how to shrink it instead.
        case manual(String)
    }

    public let id: String
    public let title: String
    /// Absolute paths. `~` is the home folder, and `*` matches any part of a single name.
    public let paths: [String]
    public let category: StorageCategory
    public let safety: SafetyLevel
    public let cleanup: Cleanup
    /// Whether System Settings counts this in "System Data".
    public let countsAsSystemData: Bool
    /// Whether to list this under Suggestions.
    public let suggest: Bool
    public let whatItIs: String
    public let ifDeleted: String
    /// How to describe individual items inside this location.
    public let insideNote: String?
    /// Safety of individual items inside this location, when different from the location itself.
    public let insideSafety: SafetyLevel?

    public init(
        id: String,
        title: String,
        paths: [String],
        category: StorageCategory,
        safety: SafetyLevel,
        cleanup: Cleanup,
        systemData: Bool = false,
        suggest: Bool = false,
        whatItIs: String,
        ifDeleted: String,
        insideNote: String? = nil,
        insideSafety: SafetyLevel? = nil
    ) {
        self.id = id
        self.title = title
        self.paths = paths
        self.category = category
        self.safety = safety
        self.cleanup = cleanup
        self.countsAsSystemData = systemData
        self.suggest = suggest
        self.whatItIs = whatItIs
        self.ifDeleted = ifDeleted
        self.insideNote = insideNote
        self.insideSafety = insideSafety
    }

    public var manualSteps: String? {
        if case .manual(let steps) = cleanup { return steps }
        return nil
    }
}

/// A plain-language description of a path.
public struct Explanation: Sendable {
    public let location: KnownLocation
    /// True when the path is the location itself rather than something inside it.
    public let isExact: Bool
    /// Names matched by wildcards in the location's path, e.g. an app's bundle ID.
    public let captures: [String]
    public let headline: String
    public let whatItIs: String
    public let ifDeleted: String
    public let safety: SafetyLevel
    public let category: StorageCategory
    public let countsAsSystemData: Bool

    public var manualSteps: String? { location.manualSteps }
}

enum Wildcard {
    /// Matches `name` against a pattern where `*` stands for any run of characters.
    static func matches(_ pattern: String, _ name: String) -> Bool {
        let p = Array(pattern.utf8)
        let s = Array(name.utf8)
        let star = UInt8(ascii: "*")
        var pi = 0
        var si = 0
        var starIndex = -1
        var mark = 0
        while si < s.count {
            if pi < p.count && p[pi] == star {
                starIndex = pi
                mark = si
                pi += 1
            } else if pi < p.count && p[pi] == s[si] {
                pi += 1
                si += 1
            } else if starIndex >= 0 {
                pi = starIndex + 1
                mark += 1
                si = mark
            } else {
                return false
            }
        }
        while pi < p.count && p[pi] == star { pi += 1 }
        return pi == p.count
    }
}

/// A trie of path components, so a whole scan can be matched against every known location
/// in a single pass.
final class PatternTrie: @unchecked Sendable {
    struct Terminal {
        let index: Int
        let pattern: [String]
        let literalCount: Int
    }

    final class Node {
        var literals: [String: Node] = [:]
        var globs: [(pattern: String, node: Node)] = []
        var terminals: [Terminal] = []
    }

    let root = Node()

    func insert(_ components: [String], index: Int) {
        var node = root
        var literalCount = 0
        for component in components {
            if component.contains("*") {
                if let existing = node.globs.first(where: { $0.pattern == component }) {
                    node = existing.node
                } else {
                    let next = Node()
                    node.globs.append((component, next))
                    node = next
                }
            } else {
                literalCount += 1
                if let existing = node.literals[component] {
                    node = existing
                } else {
                    let next = Node()
                    node.literals[component] = next
                    node = next
                }
            }
        }
        node.terminals.append(Terminal(index: index, pattern: components, literalCount: literalCount))
    }

    func advance(_ states: [Node], _ name: String) -> [Node] {
        var next: [Node] = []
        for state in states {
            if let literal = state.literals[name] { next.append(literal) }
            for glob in state.globs where Wildcard.matches(glob.pattern, name) {
                next.append(glob.node)
            }
        }
        return next
    }

    func advance(_ states: [Node], through names: [String]) -> [Node] {
        var current = states
        for name in names {
            if current.isEmpty { break }
            current = advance(current, name)
        }
        return current
    }

    /// The most specific location ending at one of these states: more literal (non-wildcard)
    /// components win, then whichever comes first in the catalog.
    static func best(in states: [Node]) -> Terminal? {
        var best: Terminal?
        for state in states {
            for terminal in state.terminals {
                guard let current = best else {
                    best = terminal
                    continue
                }
                if terminal.literalCount > current.literalCount
                    || (terminal.literalCount == current.literalCount && terminal.index < current.index) {
                    best = terminal
                }
            }
        }
        return best
    }
}

/// Everything Data Explorer knows about where macOS and apps keep things.
public struct KnowledgeBase: Sendable {
    public let home: String
    public let locations: [KnownLocation]
    let trie: PatternTrie
    private let indexByID: [String: Int]
    /// Expanded, wildcard-free location paths. Used to stop deleting folders that contain them.
    public let literalPaths: [String]

    public struct Match: Sendable {
        public let location: KnownLocation
        public let index: Int
        public let depth: Int
        public let isExact: Bool
        public let captures: [String]
    }

    public init(home: String, locations: [KnownLocation]) {
        let home = home.count > 1 && home.hasSuffix("/") ? String(home.dropLast()) : home
        self.home = home
        self.locations = locations
        let trie = PatternTrie()
        var indexByID: [String: Int] = [:]
        var literalPaths: [String] = []
        for (index, location) in locations.enumerated() {
            indexByID[location.id] = index
            for raw in location.paths {
                let expanded = Self.expand(raw, home: home)
                trie.insert(Self.components(of: expanded), index: index)
                if !expanded.contains("*") { literalPaths.append(expanded) }
            }
        }
        self.trie = trie
        self.indexByID = indexByID
        self.literalPaths = literalPaths
    }

    /// The built-in catalog for the current user.
    public static func standard(home: String = NSHomeDirectory()) -> KnowledgeBase {
        KnowledgeBase(home: home, locations: Catalog.locations)
    }

    public static func expand(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        return path
    }

    public static func components(of path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    public func location(id: String) -> KnownLocation? {
        indexByID[id].map { locations[$0] }
    }

    /// The most specific known location that is, or contains, the path.
    public func match(path: String) -> Match? {
        let comps = Self.components(of: path)
        var states = [trie.root]
        var best: (terminal: PatternTrie.Terminal, depth: Int)?
        if let terminal = PatternTrie.best(in: states) { best = (terminal, 0) }
        for (offset, name) in comps.enumerated() {
            states = trie.advance(states, name)
            if states.isEmpty { break }
            if let terminal = PatternTrie.best(in: states) { best = (terminal, offset + 1) }
        }
        guard let best else { return nil }
        return makeMatch(best.terminal, depth: best.depth, components: comps)
    }

    func makeMatch(_ terminal: PatternTrie.Terminal, depth: Int, components: [String]) -> Match {
        var captures: [String] = []
        for (offset, part) in terminal.pattern.enumerated() where part.contains("*") && offset < components.count {
            captures.append(components[offset])
        }
        return Match(
            location: locations[terminal.index],
            index: terminal.index,
            depth: depth,
            isExact: depth == components.count,
            captures: captures
        )
    }

    /// A plain-language description of what's at a path and whether it's safe to delete.
    public func explain(path: String, isDirectory: Bool) -> Explanation {
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()
        let hint = FileTypeHints.hint(forExtension: ext, isDirectory: isDirectory)

        guard let match = match(path: path) else {
            return Explanation(
                location: Catalog.unknown,
                isExact: false,
                captures: [],
                headline: hint?.title ?? Catalog.unknown.title,
                whatItIs: hint?.description ?? Catalog.unknown.whatItIs,
                ifDeleted: Catalog.unknown.ifDeleted,
                safety: hint?.safety ?? Catalog.unknown.safety,
                category: Catalog.unknown.category,
                countsAsSystemData: true
            )
        }

        let location = match.location
        if match.isExact {
            return Explanation(
                location: location,
                isExact: true,
                captures: match.captures,
                headline: location.title,
                whatItIs: location.whatItIs,
                ifDeleted: location.ifDeleted,
                safety: location.safety,
                category: location.category,
                countsAsSystemData: location.countsAsSystemData
            )
        }

        // Inside a general area, the file type tells us more than the folder does.
        if let hint, location.cleanup == .individually, location.safety != .protected {
            return Explanation(
                location: location,
                isExact: false,
                captures: match.captures,
                headline: hint.title,
                whatItIs: hint.description,
                ifDeleted: hint.safety == .protected ? location.ifDeleted : hint.ifDeleted,
                safety: hint.safety,
                category: location.category,
                countsAsSystemData: location.countsAsSystemData
            )
        }

        return Explanation(
            location: location,
            isExact: false,
            captures: match.captures,
            headline: "Inside \(location.title)",
            whatItIs: location.insideNote ?? location.whatItIs,
            ifDeleted: location.ifDeleted,
            safety: location.insideSafety ?? location.safety,
            category: location.category,
            countsAsSystemData: location.countsAsSystemData
        )
    }
}
