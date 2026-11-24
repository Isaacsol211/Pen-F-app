import Foundation

/// A tiny DOM for the small XML documents the camera returns.
final class XMLNode {
    let name: String
    let attributes: [String: String]
    var children: [XMLNode] = []
    var text = ""

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    func children(_ name: String) -> [XMLNode] { children.filter { $0.name == name } }

    /// Trimmed text of the first child element with this name.
    func value(_ name: String) -> String? { children.first { $0.name == name }?.trimmedText }

    func descendants(named name: String) -> [XMLNode] {
        children.flatMap { ($0.name == name ? [$0] : []) + $0.descendants(named: name) }
    }

    func firstDescendant(named names: Set<String>) -> XMLNode? {
        for c in children {
            if names.contains(c.name) { return c }
            if let found = c.firstDescendant(named: names) { return found }
        }
        return nil
    }
}

enum MiniXML {
    /// Parses camera XML. The camera declares `encoding="Shift-JIS"`, which libxml may not
    /// recognise; the content is ASCII, so the declaration is stripped before parsing.
    static func parse(_ data: Data) -> XMLNode? {
        guard !data.isEmpty else { return nil }
        var text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .shiftJIS)
            ?? String(decoding: data, as: UTF8.self)
        if let range = text.range(of: #"encoding\s*=\s*"[^"]*""#, options: .regularExpression) {
            text.removeSubrange(range)
        }
        let parser = XMLParser(data: Data(text.utf8))
        let delegate = Delegate()
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.root
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var root: XMLNode?
        private var stack: [XMLNode] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let node = XMLNode(name: elementName, attributes: attributeDict)
            if let parent = stack.last { parent.children.append(node) } else if root == nil { root = node }
            stack.append(node)
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            _ = stack.popLast()
        }
    }
}

/// The camera's own list of supported commands (`get_commandlist.cgi`).
/// Shape: <oishare><cgi name="exec_takemotion"><http_method type="get"><cmd1 name="com"><param1 name="starttake">…
struct CommandList {
    private(set) var cgis: [String: XMLNode] = [:]
    private(set) var version: String?

    init(root: XMLNode? = nil) {
        guard let root else { return }
        version = root.value("version")
        for cgi in root.descendants(named: "cgi") {
            if let name = cgi.attributes["name"] { cgis[name] = cgi }
        }
    }

    var isEmpty: Bool { cgis.isEmpty }

    /// Values of `com=` (param1) a command accepts.
    func subcommands(of cgi: String) -> [String] {
        guard let node = cgis[cgi] else { return [] }
        return node.descendants(named: "param1").compactMap { $0.attributes["name"] }
    }

    /// When the list could not be read, assume support and let the camera say no.
    func supports(_ cgi: String, _ subcommand: String) -> Bool {
        guard !isEmpty, cgis[cgi] != nil else { return true }
        return subcommands(of: cgi).contains(subcommand)
    }

    /// lvqty values listed under switch_cammode ▸ mode=rec.
    var liveViewSizes: [String] {
        guard let node = cgis["switch_cammode"] else { return [] }
        return node.descendants(named: "param2").compactMap { $0.attributes["name"] }
            .filter { $0.contains("x") }
    }
}
