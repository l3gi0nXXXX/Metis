package metis.core.tools.fs_utils

import std.collection.ArrayList
import std.fs.{FileInfo, Directory, Path, exists}
import std.sort.sort

public func listTree(path: String): String {
    let treePath = Path(path)
    if (!treePath.isAbsolute()) {
        return "Path must be absolute"
    } else if (!exists(treePath)) {
        return "${path} does not exist"
    }

    if (!exists(treePath)) {
        return "Directory does not exist: ${treePath}"
    }

    let builder = StringBuilder()
    treeRecursive(treePath, "", true, builder)
    return builder.toString()
}

private func treeRecursive(currentPath: Path, prefix: String, isLast: Bool, builder: StringBuilder): Unit {
    if (!exists(currentPath)) {
        return
    }
    let itemName = currentPath.fileName

    if (prefix.size > 0) {
        builder.append(prefix)
        if (isLast) {
            builder.append("└── ")
        } else {
            builder.append("├── ")
        }
    }

    builder.append(itemName)
    builder.append("\n")

    if (FileInfo(currentPath).isRegular()) {
        return
    }

    let items = ArrayList<FileInfo>()
    for (item in Directory.readFrom(currentPath)) {
        if (!ignored(item.path)) {
            items.add(item)
        }
    }

    sort(items, by: { a, b => a.path.fileName.compare(b.path.fileName) })

    for (i in 0..items.size) {
        let item = items[i]
        let isLastItem = i == items.size - 1
        let newPrefix = prefix + if (isLast) { "    " } else { "│   " }
        treeRecursive(item.path, newPrefix, isLastItem, builder)
    }
}