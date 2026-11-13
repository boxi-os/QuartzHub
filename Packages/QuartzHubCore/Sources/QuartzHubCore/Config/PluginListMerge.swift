import Foundation

/// The plugin list after the CLI changed it on disk while the page holds edits of its own (the
/// layout stage moves and edits entries; saving or deleting a frame runs `quartz plugin add` or
/// `remove`). Taking the disk's list whole dropped the stage's unsaved edits without a word
/// (review 2026-11-13, H2).
///
/// A three-way merge over the entries, each known by name, source and how many came before it
/// with the same two: what the CLI added comes in at its place on disk, what it removed goes,
/// an entry the page did not touch takes the disk's version, an entry the page edited keeps the
/// edit. The page's order stays.
public enum PluginListMerge {
  public static func merge(base: [PluginEntry], local: [PluginEntry], disk: [PluginEntry]) -> [PluginEntry] {
    let baseByKey = Dictionary(uniqueKeysWithValues: zip(keys(base), base))
    let diskKeys = keys(disk)
    let diskByKey = Dictionary(uniqueKeysWithValues: zip(diskKeys, disk))

    var merged: [(key: Key, entry: PluginEntry)] = []
    for (key, entry) in zip(keys(local), local) {
      guard let onDisk = diskByKey[key] else {
        // Gone from disk: the CLI removed it, unless the page added it itself.
        if baseByKey[key] == nil { merged.append((key, entry)) }
        continue
      }
      merged.append((key, baseByKey[key] == entry ? onDisk : entry))
    }
    // New on disk: after the entry that comes before it there, or first.
    let present = Set(merged.map(\.key))
    for (index, key) in diskKeys.enumerated() where baseByKey[key] == nil && !present.contains(key) {
      let after = diskKeys[..<index].last { k in merged.contains { $0.key == k } }
      let at = after.flatMap { k in merged.lastIndex { $0.key == k } }.map { $0 + 1 } ?? 0
      merged.insert((key, diskByKey[key]!), at: at)
    }
    return merged.map(\.entry)
  }

  struct Key: Hashable {
    let signature: String
    let occurrence: Int
  }

  static func keys(_ entries: [PluginEntry]) -> [Key] {
    var seen: [String: Int] = [:]
    return entries.map { entry in
      let signature = "\(entry.name)\n\(entry.source.map(JSJSON.compact) ?? "")"
      defer { seen[signature, default: 0] += 1 }
      return Key(signature: signature, occurrence: seen[signature, default: 0])
    }
  }
}
