package metis.core.tools

/**
 * 轻量媒体/文档探针工具（对齐「Agent + function calling + 本地解析」模式）：
 * 不引入 PDF/图像重型库，仅对常见格式做文件头解析或启发式统计，结果供模型与用户参考。
 */
import magic.dsl.{tool, toolset}
import magic.prelude.*

import metis.io.PrintUtils

import std.collection.ArrayList
import std.fs.{Path, File, exists}

private let PDF_PAGE_PATTERN_BYTES: Array<Byte> = "/Type /Page".toArray()

private func byteU32(b: Byte): UInt32 {
    UInt32(UInt8(b))
}

private func beUInt16(data: Array<Byte>, i: Int64): UInt32 {
    (byteU32(data[i]) << 8) | byteU32(data[i + 1])
}

private func beUInt32(data: Array<Byte>, i: Int64): UInt32 {
    (byteU32(data[i]) << 24) | (byteU32(data[i + 1]) << 16) | (byteU32(data[i + 2]) << 8) | byteU32(data[i + 3])
}

private func leUInt16(data: Array<Byte>, i: Int64): UInt32 {
    byteU32(data[i]) | (byteU32(data[i + 1]) << 8)
}

private func isPngSignature(data: Array<Byte>): Bool {
    data.size >= 8 &&
        UInt8(data[0]) == 137u8 &&
        UInt8(data[1]) == 80u8 &&
        UInt8(data[2]) == 78u8 &&
        UInt8(data[3]) == 71u8 &&
        UInt8(data[4]) == 13u8 &&
        UInt8(data[5]) == 10u8 &&
        UInt8(data[6]) == 26u8 &&
        UInt8(data[7]) == 10u8
}

private func isJpegSignature(data: Array<Byte>): Bool {
    data.size >= 3 &&
        UInt8(data[0]) == 255u8 &&
        UInt8(data[1]) == 216u8 &&
        UInt8(data[2]) == 255u8
}

private func isGifSignature(data: Array<Byte>): Bool {
    data.size >= 6 &&
        UInt8(data[0]) == 71u8 &&
        UInt8(data[1]) == 73u8 &&
        UInt8(data[2]) == 70u8 &&
        UInt8(data[3]) == 56u8 &&
        (UInt8(data[4]) == 55u8 || UInt8(data[4]) == 57u8) &&
        UInt8(data[5]) == 97u8
}

private func isPdfSignature(data: Array<Byte>): Bool {
    data.size >= 5 &&
        UInt8(data[0]) == 37u8 &&
        UInt8(data[1]) == 80u8 &&
        UInt8(data[2]) == 68u8 &&
        UInt8(data[3]) == 70u8 &&
        UInt8(data[4]) == 45u8
}

private func pngDimensions(data: Array<Byte>): Option<(UInt32, UInt32)> {
    if (!isPngSignature(data) || data.size < 24) {
        return None
    }
    // IHDR: 13 bytes data at offset 16 after 8-byte signature + 4 length + 4 "IHDR"
    let w = beUInt32(data, 16)
    let h = beUInt32(data, 20)
    Some((w, h))
}

private func gifDimensions(data: Array<Byte>): Option<(UInt32, UInt32)> {
    if (!isGifSignature(data) || data.size < 10) {
        return None
    }
    let w = leUInt16(data, 6)
    let h = leUInt16(data, 8)
    Some((w, h))
}

private func jpegDimensions(data: Array<Byte>): Option<(UInt32, UInt32)> {
    if (!isJpegSignature(data)) {
        return None
    }
    var i: Int64 = 2
    let n = Int64(data.size)
    while (i + 1 < n) {
        if (UInt8(data[i]) != 255u8) {
            i += 1
            continue
        }
        var m = UInt8(data[i + 1])
        if (m == 255u8) {
            i += 1
            continue
        }
        if (m == 216u8) {
            // SOI
            i += 2
            continue
        }
        if (m == 217u8) {
            // EOI
            break
        }
        if (m >= 208u8 && m <= 215u8) {
            i += 2
            continue
        }
        if (i + 3 >= n) {
            break
        }
        let segLen = beUInt16(data, i + 2)
        if (segLen < 2) {
            break
        }
        let segTotal = Int64(segLen) + 2
        // SOF0 / SOF2 / SOF1 ...
        if (m == 192u8 || m == 194u8 || m == 193u8 || m == 195u8 || m == 197u8 || m == 198u8 || m == 199u8 ||
            m == 201u8 || m == 202u8 || m == 203u8 || m == 205u8 || m == 206u8 || m == 207u8) {
            if (i + 8 < n) {
                let h = beUInt16(data, i + 5)
                let w = beUInt16(data, i + 7)
                return Some((w, h))
            }
            return None
        }
        i += segTotal
    }
    None
}

/** 统计 ASCII 子串 "/Type /Page" 出现次数，并排除 "/Type /Pages" 误匹配。 */
private func pdfApproxPageCountFromBytes(data: Array<Byte>): Int64 {
    let pat = PDF_PAGE_PATTERN_BYTES
    let pn = Int64(pat.size)
    let dn = Int64(data.size)
    if (pn == 0 || dn < pn) {
        return 0
    }
    var count: Int64 = 0
    var i: Int64 = 0
    while (i + pn <= dn) {
        var ok = true
        var j: Int64 = 0
        while (j < pn) {
            if (UInt8(data[i + j]) != UInt8(pat[j])) {
                ok = false
                break
            }
            j += 1
        }
        if (ok) {
            if (i + pn < dn && UInt8(data[i + pn]) == 115u8) {
                // 's' -> /Type /Pages
                i += 1
                continue
            }
            count += 1
        }
        i += 1
    }
    count
}

private func sniffFormat(data: Array<Byte>, ext: String): String {
    if (isPngSignature(data)) {
        return "png"
    }
    if (isGifSignature(data)) {
        return "gif"
    }
    if (isJpegSignature(data)) {
        return "jpeg"
    }
    if (isPdfSignature(data)) {
        return "pdf"
    }
    let e = ext.toAsciiLower()
    if (e == "png") {
        return "png(extension-only)"
    }
    if (e == "jpg" || e == "jpeg") {
        return "jpeg(extension-only)"
    }
    if (e == "gif") {
        return "gif(extension-only)"
    }
    if (e == "pdf") {
        return "pdf(extension-only)"
    }
    "unknown"
}

@toolset
public class BasicMediaToolset {
    @tool[
        description: "Inspects a local media or PDF file (absolute path): file size, format from magic bytes, image width/height for PNG/JPEG/GIF, and approximate PDF page count via /Type /Page heuristic. Max file size 8 MiB. PDF page count is a heuristic and may differ from the true value; for exact counts use a dedicated PDF tool or shell.",
        parameters: { filePath: "Absolute path to a .png, .jpg/.jpeg, .gif, or .pdf file" }
    ]
    public func basicMediaInspect(filePath: String): String {
        if (!Path(filePath).isAbsolute()) {
            return "File path must be absolute"
        }
        if (!exists(Path(filePath))) {
            return "File does not exist: ${filePath}"
        }
        let ext = Path(filePath).extensionName
        PrintUtils.printTool("Basic Media Inspect", shortMessage: filePath)
        let maxBytes: Int64 = 8 * 1024 * 1024
        let data = try {
            File.readFrom(filePath)
        } catch (e: Exception) {
            let msg = "Failed to read file: ${e}"
            PrintUtils.printToolResult(msg)
            return msg
        }
        if (Int64(data.size) > maxBytes) {
            let msg =
                "File too large (${data.size} bytes). This tool only reads up to ${maxBytes} bytes. Use shell or split the task."
            PrintUtils.printToolResult(msg)
            return msg
        }
        let fmt = sniffFormat(data, ext)
        let lines = ArrayList<String>()
        lines.add("path: ${filePath}")
        lines.add("sizeBytes: ${data.size}")
        lines.add("extension: ${ext}")
        lines.add("detectedFormat: ${fmt}")
        match (pngDimensions(data)) {
            case Some((w, h)) => lines.add("dimensionsPx: ${w} x ${h} (PNG IHDR)")
            case None => ()
        }
        match (jpegDimensions(data)) {
            case Some((w, h)) => lines.add("dimensionsPx: ${w} x ${h} (JPEG SOF)")
            case None => ()
        }
        match (gifDimensions(data)) {
            case Some((w, h)) => lines.add("dimensionsPx: ${w} x ${h} (GIF logical screen)")
            case None => ()
        }
        if (isPdfSignature(data)) {
            let pages = pdfApproxPageCountFromBytes(data)
            lines.add("pdfApproxPageObjects: ${pages} (heuristic; not guaranteed equal to viewer page count)")
        }
        let result = String.join(lines.toArray(), delimiter: "\n")
        PrintUtils.printToolResult(result)
        return result
    }

    @tool[
        description:
            "Returns width and height in pixels for PNG, JPEG, or GIF at an absolute path by parsing headers only. Max file size 8 MiB. Fails if the format is not supported or dimensions cannot be located.",
        parameters: { filePath: "Absolute path to .png, .jpg/.jpeg, or .gif" }
    ]
    public func imageReadDimensions(filePath: String): String {
        if (!Path(filePath).isAbsolute()) {
            return "File path must be absolute"
        }
        if (!exists(Path(filePath))) {
            return "File does not exist: ${filePath}"
        }
        PrintUtils.printTool("Image Dimensions", shortMessage: filePath)
        let maxBytes: Int64 = 8 * 1024 * 1024
        let data = try {
            File.readFrom(filePath)
        } catch (e: Exception) {
            let msg = "Failed to read file: ${e}"
            PrintUtils.printToolResult(msg)
            return msg
        }
        if (Int64(data.size) > maxBytes) {
            let msg = "File too large (${data.size} bytes); max ${maxBytes}."
            PrintUtils.printToolResult(msg)
            return msg
        }
        if (let Some((w, h)) <- pngDimensions(data)) {
            let out = "PNG ${w} x ${h}"
            PrintUtils.printToolResult(out)
            return out
        }
        if (let Some((w, h)) <- jpegDimensions(data)) {
            let out = "JPEG ${w} x ${h}"
            PrintUtils.printToolResult(out)
            return out
        }
        if (let Some((w, h)) <- gifDimensions(data)) {
            let out = "GIF ${w} x ${h}"
            PrintUtils.printToolResult(out)
            return out
        }
        let out = "Could not read dimensions (not PNG/JPEG/GIF or header missing)."
        PrintUtils.printToolResult(out)
        return out
    }
}
