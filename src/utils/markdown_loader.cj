package metis.utils

import magic.utils.readFile

import std.fs.Path
import std.collection.{HashMap, enumerate}

protected func loadMarkdown(filePath: Path): (HashMap<String, String>, String) {
        let metadata = HashMap<String, String>()

        let fileContent = readFile(filePath)
        let lines = fileContent.split("\n")
        var pivot = -1
        for ((idx, line) in enumerate(lines)) {
            if (line.startsWith("---")) {
                pivot = idx
                break
            }
        }
        // Markdown does not have metadata section
        if (pivot == -1) {
            return (metadata, fileContent)
        }
        // Parse metadata section
        for (line in lines[0..pivot]) {
            let items = line.split(":")
            if (items.size == 2) {
                metadata.add(items[0].trimAscii(), items[1].trimAscii())
            }
        }
        // The rest of the lines are the Markdown content
        return (metadata, String.join(lines[pivot+1..], delimiter: "\n"))
    }