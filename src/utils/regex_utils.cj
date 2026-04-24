package metis.utils

import std.regex.{Regex, MatchData}

protected class RegexUtils {
    /**
    * Replace all occurrences of a pattern in a string with a replacement function.
    *
    * @param str The input string to search and replace in.
    * @param pattern The regex pattern to search for.
    * @param replacement A function that takes a MatchData object and returns the replacement string.
    * @return The modified string with all occurrences replaced.
    */
    protected static func replaceAll(str: String, pattern: String, replacement: (MatchData) -> String): String {
        let strBuilder = StringBuilder()
        var prev = 0
        for (md in (Regex(pattern).findAll(str, group: true))) {
            strBuilder.append(str[prev..md.matchPosition().start])
            strBuilder.append(replacement(md))
            prev = md.matchPosition().end
        }
        strBuilder.append(str[prev..])
        return strBuilder.toString()
    }
}