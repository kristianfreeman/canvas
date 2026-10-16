/// The error box a native panel shows when its render fails, as ops built
/// from kit elements. Ids are negative so they never meet the runtime's.
enum NativeErrorNodes {
    static let boxID = -1

    static func ops(message: String) -> [[String: Any]] {
        [
            ["op": "create", "id": -1, "type": "Card", "props": ["padding": 14]],
            ["op": "create", "id": -2, "type": "Stack", "props": ["gap": 6]],
            ["op": "create", "id": -3, "type": "Text",
             "props": ["size": "sm", "weight": "semibold", "color": "danger"]],
            ["op": "text", "id": -4, "text": "Error"],
            ["op": "create", "id": -5, "type": "Text", "props": ["mono": true, "size": "sm"]],
            ["op": "text", "id": -6, "text": message],
            ["op": "append", "parent": -3, "child": -4],
            ["op": "append", "parent": -5, "child": -6],
            ["op": "append", "parent": -2, "child": -3],
            ["op": "append", "parent": -2, "child": -5],
            ["op": "append", "parent": -1, "child": -2],
            ["op": "append", "parent": 0, "child": boxID]
        ]
    }

    static let removal: [[String: Any]] = [["op": "remove", "parent": 0, "child": boxID]]
}
