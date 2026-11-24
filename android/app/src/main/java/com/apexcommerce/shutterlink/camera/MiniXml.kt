package com.apexcommerce.shutterlink.camera

import android.util.Xml
import org.xmlpull.v1.XmlPullParser
import java.io.StringReader
import java.nio.charset.Charset

/** A tiny DOM for the small XML documents cameras return (port of XML.swift). */
class XmlNode(val name: String, val attributes: Map<String, String>) {
    val children = mutableListOf<XmlNode>()
    var text = StringBuilder()

    val trimmedText: String get() = text.toString().trim()

    fun child(name: String): XmlNode? = children.firstOrNull { it.name == name }
    fun children(name: String): List<XmlNode> = children.filter { it.name == name }

    /** Trimmed text of the first child element with this name. */
    fun value(name: String): String? = child(name)?.trimmedText

    fun descendants(name: String): List<XmlNode> {
        val result = mutableListOf<XmlNode>()
        for (c in children) {
            if (c.name == name) result.add(c)
            result.addAll(c.descendants(name))
        }
        return result
    }

    fun firstDescendant(vararg names: String): XmlNode? {
        for (c in children) {
            if (c.name in names) return c
            c.firstDescendant(*names)?.let { return it }
        }
        return null
    }
}

object MiniXml {
    private val encodingDecl = Regex("""encoding\s*=\s*"[^"]*"""")

    fun parse(data: ByteArray): XmlNode? {
        if (data.isEmpty()) return null
        val text = try {
            val utf8 = String(data, Charsets.UTF_8)
            if (utf8.contains('�')) String(data, Charset.forName("Shift_JIS")) else utf8
        } catch (ignored: Exception) {
            String(data, Charsets.UTF_8)
        }
        return parse(text)
    }

    /**
     * Parses camera XML. Olympus declares `encoding="Shift-JIS"`; the content is ASCII, so the
     * declaration is stripped. Namespaced names keep their prefix ("dc:title", "pana:X_CamCapability").
     */
    fun parse(source: String): XmlNode? {
        if (source.isBlank()) return null
        val text = encodingDecl.replaceFirst(source, "")
        return try {
            val parser = Xml.newPullParser()
            parser.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, false)
            parser.setInput(StringReader(text))
            var root: XmlNode? = null
            val stack = ArrayDeque<XmlNode>()
            var event = parser.eventType
            while (event != XmlPullParser.END_DOCUMENT) {
                when (event) {
                    XmlPullParser.START_TAG -> {
                        val attrs = HashMap<String, String>()
                        for (i in 0 until parser.attributeCount) attrs[parser.getAttributeName(i)] = parser.getAttributeValue(i)
                        val node = XmlNode(parser.name, attrs)
                        val parent = stack.lastOrNull()
                        if (parent != null) parent.children.add(node) else if (root == null) root = node
                        stack.addLast(node)
                    }
                    // next() merges text, CDATA and entities (&lt; → <) into one TEXT event.
                    XmlPullParser.TEXT -> stack.lastOrNull()?.text?.append(parser.text ?: "")
                    XmlPullParser.END_TAG -> stack.removeLastOrNull()
                }
                event = try {
                    parser.next()
                } catch (ignored: Exception) {
                    break
                }
            }
            root
        } catch (ignored: Exception) {
            null
        }
    }
}

/**
 * The Olympus camera's own list of supported commands (`get_commandlist.cgi`).
 * Shape: <oishare><cgi name="exec_takemotion"><http_method type="get"><cmd1 name="com"><param1 name="starttake">…
 */
class CommandList(root: XmlNode? = null) {
    val cgis: Map<String, XmlNode>
    val version: String?

    init {
        val map = HashMap<String, XmlNode>()
        root?.descendants("cgi")?.forEach { cgi -> cgi.attributes["name"]?.let { map[it] = cgi } }
        cgis = map
        version = root?.value("version")
    }

    val isEmpty: Boolean get() = cgis.isEmpty()

    /** Values of `com=` (param1) a command accepts. */
    fun subcommands(cgi: String): List<String> =
        cgis[cgi]?.descendants("param1")?.mapNotNull { it.attributes["name"] } ?: emptyList()

    /** When the list could not be read, assume support and let the camera say no. */
    fun supports(cgi: String, subcommand: String): Boolean {
        if (isEmpty || cgis[cgi] == null) return true
        return subcommands(cgi).contains(subcommand)
    }

    /** lvqty values listed under switch_cammode ▸ mode=rec. */
    val liveViewSizes: List<String>
        get() = cgis["switch_cammode"]?.descendants("param2")?.mapNotNull { it.attributes["name"] }
            ?.filter { it.contains("x") } ?: emptyList()
}
