import AppKit
import SwiftUI

@MainActor @Observable final class Model {
  var items = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon"]
  var selection: String? = "Beta"
  func move(_ name: String, by delta: Int) {
    guard let from = items.firstIndex(of: name) else { return }
    let to = from + delta
    guard items.indices.contains(to) else { return }
    items.move(fromOffsets: [from], toOffset: delta > 0 ? to + 1 : to)
    log()
    AccessibilityNotification.Announcement("\(name) ist jetzt an Position \(to + 1) von \(items.count).").post()
  }
  func log() { print("order:", items.joined(separator: ","), "selection:", selection ?? "-"); fflush(stdout) }
}

struct MoveKey: FocusedValueKey { typealias Value = (Int) -> Void }
extension FocusedValues { var move: MoveKey.Value? { get { self[MoveKey.self] } set { self[MoveKey.self] = newValue } } }

struct ContentView: View {
  @State var model: Model
  var body: some View {
    List(selection: $model.selection) {
      ForEach(model.items, id: \.self) { item in
        Text(item)
          .tag(item)
          .accessibilityIdentifier("row.\(item)")
          .accessibilityAction(named: "Nach oben") { model.move(item, by: -1) }
          .accessibilityAction(named: "Nach unten") { model.move(item, by: 1) }
          .contextMenu {
            Button("Nach oben") { model.move(item, by: -1) }
            Button("Nach unten") { model.move(item, by: 1) }
          }
      }
      .onMove { from, to in model.items.move(fromOffsets: from, toOffset: to); model.log() }
    }
    .accessibilityIdentifier("list")
    .focusedSceneValue(\.move, { delta in if let s = model.selection { model.move(s, by: delta) } })
  }
}

struct MoveCommands: Commands {
  @FocusedValue(\.move) var move
  var body: some Commands {
    CommandMenu("Anordnen") {
      Button("Nach oben") { move?(-1) }.keyboardShortcut(.upArrow, modifiers: [.option, .command]).disabled(move == nil)
      Button("Nach unten") { move?(1) }.keyboardShortcut(.downArrow, modifiers: [.option, .command]).disabled(move == nil)
    }
  }
}

struct ReorderApp: App {
  @State var model = Model()
  var body: some Scene {
    WindowGroup("reorder-spike") { ContentView(model: model).frame(width: 300, height: 260) }
      .commands { MoveCommands() }
  }
}
NSApplication.shared.setActivationPolicy(.regular)
ReorderApp.main()
