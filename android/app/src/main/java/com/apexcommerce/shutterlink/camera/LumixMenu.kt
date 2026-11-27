package com.apexcommerce.shutterlink.camera

// The extra LUMIX settings (drive mode, Photo Style, filters, AF mode…), read from the camera's own
// menu (`getinfo&type=allmenu`); port of LumixMenu.swift. The menu lists every value with the exact
// `setsetting` strings and an English name, so nothing here is hard-coded per model.

/** One of the extra LUMIX settings. Built while the menu is parsed. */
class LumixSetting(
    /** Property name in the app. Drive mode uses the shared "drivemode" so it gets the Drive button. */
    val name: String,
    /** The `type` for getsetting/setsetting. */
    val type: String,
    val title: String,
) {
    /** "value", or "value|value2" when the camera wants a second part (burst speed, timer length…). */
    val options = mutableListOf<String>()
    val labels = LinkedHashMap<String, String>()
    /**
     * The menu items behind each option (its own and the choice it sits under, e.g. Burst), to look up
     * in `curmenu` whether it's available right now.
     */
    val optionItems = HashMap<String, List<String>>()
    /** The menu headings around the options (e.g. "Photo Style"), which `curmenu` can switch off. */
    val headingItems = mutableListOf<String>()
}

/** Colour-temperature white balance: `whitebalance=color_temp&value2=<kelvin>`. */
data class LumixKelvin(val min: Int, val max: Int, val step: Int, val itemId: String?) {
    val options: List<String> get() = (min..max step maxOf(step, 1)).map { it.toString() }
}

/** What `getinfo&type=curmenu` says about a menu item. */
data class LumixMenuState(val enabled: Boolean, val value: String?)

object LumixMenu {
    class Wanted(val type: String, val name: String, val title: String)

    /** The settings offered, in display order: cmd_type, property name, title. */
    val wanted = listOf(
        Wanted("drivemode", "drivemode", "Drive"),
        Wanted("colormode", "colormode", "Photo Style"),
        Wanted("filter_setting", "filter_setting", "Filter"),
        Wanted("creativectrl", "creativectrl", "Creative Control"),
        Wanted("afmode", "afmode", "AF mode"),
        Wanted("lightmetering", "lightmetering", "Metering"),
        Wanted("quality", "quality", "Picture quality"),
        Wanted("aspectratio", "aspectratio", "Aspect ratio"),
        Wanted("pictsize", "pictsize", "Picture size"),
        Wanted("flash", "flash", "Flash"),
        Wanted("peaking", "peaking", "Peaking on the camera"),
        Wanted("videoformat", "videoformat", "Video format"),
        Wanted("videoquality", "videoquality", "Video quality"),
    )
    const val KELVIN_NAME = "colortemp"
    const val KELVIN_TITLE = "Colour temperature"

    /** The camera puts this where a value is filled in at run time; it is never sent. */
    private const val PLACEHOLDER = "__value__"

    class Parsed(val settings: List<LumixSetting>, val kelvin: LumixKelvin?)

    /** The settings the menu offers, and colour temperature if the white balance list has it. */
    fun parse(root: XmlNode): Parsed = Parser(englishTitles(root)).read(root)

    /** Walks the menu tree: headings (Photo Style), choices (Burst ▸ SH/H/M/L) and plain values. */
    private class Parser(private val titles: Map<String, String>) {
        private val found = HashMap<String, LumixSetting>()
        private var kelvin: LumixKelvin? = null
        private val wantedTypes = wanted.associateBy { it.type }

        fun read(root: XmlNode): Parsed {
            walk(root, null, emptyList())
            val settings = wanted.mapNotNull { found[it.type] }.filter { it.options.isNotEmpty() }
            return Parsed(settings, kelvin)
        }

        private fun title(item: XmlNode): String? = item.attributes["title_id"]?.let { titles[it] }

        /** Whether a menu item has sub-items that set something. */
        private fun hasOptions(node: XmlNode): Boolean =
            node.children.any { (it.name == "item" && it.attributes["cmd_type"] != null) || hasOptions(it) }

        private fun setting(type: String, spec: Wanted) = found.getOrPut(type) { LumixSetting(spec.name, type, spec.title) }

        private fun record(item: XmlNode, type: String, value: String, parent: XmlNode?, headings: List<String>) {
            val spec = wantedTypes[type] ?: return
            val value2 = item.attributes["cmd_value2"]?.takeIf { it.isNotEmpty() && it != PLACEHOLDER }
            val key = if (value2 != null) "$value|$value2" else value
            val setting = setting(type, spec)
            if (key in setting.options) return
            setting.options.add(key)
            val own = title(item) ?: words(value2 ?: value)
            val label = parent?.let { title(it) }?.let { "$it · $own" } ?: own
            setting.labels[key] = if (type == "drivemode") driveLabel(key) ?: label else label
            setting.optionItems[key] = listOfNotNull(item.attributes["id"], parent?.attributes?.get("id"))
            for (heading in headings) if (heading !in setting.headingItems) setting.headingItems.add(heading)
        }

        private fun visit(item: XmlNode, parent: XmlNode?, headings: List<String>) {
            val type = item.attributes["cmd_type"]
            val value = item.attributes["cmd_value"]
            if (type == "whitebalance" && value == "color_temp") {
                val lo = item.attributes["min_val"]?.toIntOrNull()
                val hi = item.attributes["max_val"]?.toIntOrNull()
                if (lo != null && hi != null && hi > lo) {
                    kelvin = LumixKelvin(lo, hi, item.attributes["step_val"]?.toIntOrNull() ?: 100, item.attributes["id"])
                    return
                }
            }
            val options = hasOptions(item)
            if (type != null && value != null && value != PLACEHOLDER && !options) {
                record(item, type, value, parent, headings)
            } else if (type != null && options) {
                // A choice whose sub-items carry the second value: Burst → SH/H/M/L. Name the choice itself
                // too, in case the camera reports it without the second part.
                val spec = wantedTypes[type]
                if (value != null && spec != null) {
                    val setting = setting(type, spec)
                    if (setting.labels[value] == null) {
                        setting.labels[value] = (if (type == "drivemode") driveLabel(value) else null) ?: title(item) ?: words(value)
                    }
                }
                walk(item, item, headings)
            } else {
                // A heading such as Photo Style or AF Mode.
                walk(item, null, headings + listOfNotNull(item.attributes["id"]))
            }
        }

        private fun walk(node: XmlNode, parent: XmlNode?, headings: List<String>) {
            for (child in node.children) {
                if (child.name == "titlelist") continue
                if (child.name == "item") visit(child, parent, headings) else walk(child, parent, headings)
            }
        }
    }

    /** `curmenu`: which items are available right now, and the value some headings carry. */
    fun parseState(root: XmlNode): Map<String, LumixMenuState> {
        val state = HashMap<String, LumixMenuState>()
        for (item in root.descendants("item")) {
            val id = item.attributes["id"] ?: continue
            state[id] = LumixMenuState(item.attributes["enable"]?.lowercase() != "no", item.attributes["value"])
        }
        return state
    }

    /** The menu's English names: title id → text. */
    fun englishTitles(root: XmlNode): Map<String, String> {
        val languages = root.descendants("language")
        val english = languages.firstOrNull { it.attributes["code"] == "en" }
            ?: languages.firstOrNull { it.attributes["default"] == "yes" } ?: return emptyMap()
        val titles = HashMap<String, String>()
        for (title in english.children("title")) {
            val id = title.attributes["id"] ?: continue
            titles[id] = title.trimmedText.replace("&apos;", "'")
        }
        return titles
    }

    /** Shorter names for drive modes than "Burst Shooting · H". */
    fun driveLabel(key: String): String? {
        val parts = key.split("|", limit = 2)
        val base = parts[0]
        val detail = parts.getOrNull(1)?.takeIf { it.isNotEmpty() }
        return when (base) {
            "normal" -> if (detail == null) "Single" else null
            "burst" -> if (detail == null) "Burst" else "Burst ${detail.uppercase()}"
            "4k_photo" -> when (detail) {
                null -> "4K Photo"
                "burst" -> "4K Burst"
                "start_stop" -> "4K Burst (S/S)"
                "pre_burst" -> "4K Pre-Burst"
                else -> null
            }
            "autobracket" -> {
                if (detail == null) return "Bracket"
                // "3shot_1/3ev" → "Bracket 3 × 1/3 EV"
                val pieces = detail.replace("ev", "").split("_").filter { it.isNotEmpty() }
                val shots = pieces.firstOrNull()?.split("s")?.firstOrNull { it.isNotEmpty() }
                if (pieces.size != 2 || shots == null) null else "Bracket $shots × ${pieces[1]} EV"
            }
            "selftimer" -> when (detail) {
                null -> "Self-timer"
                "10sec" -> "Self-timer 10 s"
                "10sec3shot" -> "Self-timer 10 s × 3"
                "2sec" -> "Self-timer 2 s"
                else -> null
            }
            "stopmotion_interval" -> when (detail) {
                null -> "Time lapse / Stop motion"
                "interval" -> "Time lapse"
                "stop_motion" -> "Stop motion"
                else -> null
            }
            else -> null
        }
    }

    /** "cinelike_d" → "Cinelike D". */
    fun words(value: String): String =
        value.replace("_", " ").split(" ").joinToString(" ") { w -> w.lowercase().replaceFirstChar { it.uppercase() } }
}
