package metis.core.tools.fs_utils

import std.fs.*

public func writeFileBasic(filePath: String, content: String, mode!: OpenMode = OpenMode.Write): String {
    return writeFileBasic(Path(filePath), content, mode: mode)
}

public func writeFileBasic(filePath: Path, content: String, mode!: OpenMode = OpenMode.Write): String {
    try {
        let file = File(filePath, mode)
        file.write(content.toArray())
        file.close()
        return "File ${filePath} written successfully!"
    } catch (e: FSException) {
        return "Parent directory does not exist, cannot open file, write failed, partial write, or file is not writable"
    } catch (e: IllegalArgumentException) {
        return "File path is empty or contains null characters"
    } catch (e: Exception) {
        return "Failed to write file: ${e}"
    }
}