package metis.utils

import std.collection.ArrayList
import std.random.Random

protected class StringUtils {
    /**
     * Split a camel case string into words.
     *
     * @param input The camel case string to split.
     * @return The string with words separated by spaces.
     */
    public static func splitCamelCase(input: String): String {
        if (input.size == 0) {
            return ""
        }

        let result = ArrayList<String>()
        let chars = input.toRuneArray()
        let currentWord = ArrayList<Rune>()

        for (i in 0..chars.size) {
            let ch = chars[i]

            // If the character is a uppercase letter and not the first character,
            // it means we are at the start of a new word.
            if (ch >= r'A' && ch <= r'Z' && i > 0) {
                // Check if the previous character is a lowercase letter or digit.
                let prevChar = chars[i-1]
                if ((prevChar >= r'a' && prevChar <= r'z') ||
                    (prevChar >= r'0' && prevChar <= r'9')) {
                    result.add(String(currentWord.toArray()))
                    currentWord.clear()
                }
            }

            currentWord.add(ch)
        }

        // Append the last word to the result.
        if (currentWord.size > 0) {
            result.add(String(currentWord.toArray()))
        }

        return String.join(result.toArray(), delimiter: " ")
    }

    protected static func randomBytes(count: Int64): String {
        let rand = Random()
        let chars = "0123456789abcdef".toRuneArray()
        var result = StringBuilder()
        for (i in 0..count) {
            let randomIndex = Int64(rand.nextInt64() % chars.size)
            result.append(chars[randomIndex])
        }
        return result.toString()
    }
}