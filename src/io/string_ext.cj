package metis.io

import std.regex.Regex

protected func removeAnsiEscape(str: String): String {
    let regex = Regex("\u{1B}\\[[\\d;]*[a-zA-Z]")
    regex.replaceAll(str, "")
}

/**
* Get Input Line size
*/
func runeSizeOf(str: String): Int64 {
    let strWithoutAnsiEscape = removeAnsiEscape(str)
    return strWithoutAnsiEscape.toRuneArray().size
}

/**
 * Compute the display width of a rune
 */
func displayWidthOf(rune: Rune): Int64 {
    // Chinese and emoji runes occupy width 2 positions
    // Unicode range of Chinese characters (rough estimate)
    if (r'\u{4e00}' <= rune && rune <= r'\u{9fff}' || // Common Chinese
        r'\u{3000}' <= rune && rune <= r'\u{303f}' || // Chinese punctuation
        r'\u{ff00}' <= rune && rune <= r'\u{ffef}' || // Full-width symbols
        r'\u{3400}' <= rune && rune <= r'\u{4dbf}' || // Rare characters (Extension A)
        r'\u{1f300}' <= rune && rune <= r'\u{1faff}') { // Emoji
        return 2
    } else {
        return 1
    }
}

/**
 * Compute the display width of a string except for the ANSI escape characters
 */
func displayWidthOf(str: String): Int64 {
    let strWithoutAnsiEscape = removeAnsiEscape(str)
    var width = 0
    for (rune in strWithoutAnsiEscape.toRuneArray()) {
        width += displayWidthOf(rune)
    }
    return width
}

/**
 * Compute the display width of a string
 */
func displayWidthOf(runeArray: Array<Rune>): Int64 {
    return displayWidthOf(String(runeArray))
}