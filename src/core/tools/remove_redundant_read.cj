package metis.core.tools

import magic.dsl.jsonable
import magic.jsonable.*
import magic.core.message.StepMessage
import magic.log.LogUtils

import metis.core.tools.fs_utils.{ReadFileParam, EditFileParam, MultiEditFileParam, BatchReadFilesParam}

import std.collection.{ArrayList, enumerate}
import std.collection.HashMap
import std.sort.sort
import stdx.encoding.json.*

/**
 * This function identifies two types of redundancy:
 * 1. Read-after-write redundancy: readFile operations that are invalidated by subsequent editFile operations on the same file
 * 2. Overlapping read redundancy: readFile operations whose ranges are contained by later readFile operations on the same file
 *
 * Algorithm Overview:
 * Phase 1: Collect all readFile and editFile operations, indexed by file path
 * Phase 2: For each file, analyze readFile operations in chronological order:
 *   - Mark reads invalidated by later edits
 *   - Mark reads whose ranges are contained by subsequent reads
 *
 * Marks redundant steps in a time series of operations.
 */
protected func removeRedundantFileReads(steps: ArrayList<StepMessage>): Unit {
    // Track the latest editFile index for each file path
    let fileEditIndexes = HashMap<String, Int64>()

    // Track readFile operations for each file: (stepIndex, ReadFileParam)
    let fileReadInfos = HashMap<String, ArrayList<(Int64, ReadFileParam)>>()

    // Phase 1: Collect all file edit and file read operations
    for ((i, step) in enumerate(steps)) {
        // Check for editFile operations
        if (let Some(tr) <- step.toolRequest && tr.name == fileEdit.name) {
            let param = EditFileParam.fromJsonValue(JsonObject(tr.args))
            fileEditIndexes[param.filePath] = i
        }
        // Check for fileMultiEdit operations
        if (let Some(tr) <- step.toolRequest && tr.name == FSToolset._fileMultiEdit) {
            let param = MultiEditFileParam.fromJsonValue(JsonObject(tr.args))
            fileEditIndexes[param.filePath] = i
        }

        // Check for readFile operations
        if (let Some(tr) <- step.toolRequest && tr.name == fileRead.name) {
            let param = ReadFileParam.fromJsonValue(JsonObject(tr.args))

            // Initialize list for this file if not exists
            if (!fileReadInfos.contains(param.filePath)) {
                fileReadInfos[param.filePath] = ArrayList<(Int64, ReadFileParam)>()
            }
            fileReadInfos[param.filePath].add((i, param))
        }

        // Check for batchReadFile operations
        // if (let Some(tr) <- step.toolRequest && tr.name == "batchReadFile") {
        //     let param = BatchReadFilesParam.fromJsonValue(JsonObject(tr.args))
        //     for (readParam in param.files) {
        //         fileReadInfos[readParam.filePath].add((i, readParam))
        //     }
        // }
    }

    // Phase 2: Analyze redundancy for each file's readFile operations
    for (filePath  in fileReadInfos.keys()) {
        let readInfos = fileReadInfos.get(filePath) ?? ArrayList<(Int64, ReadFileParam)>()

        // Sort by step index to ensure chronological processing
        // readInfos.sort({ (a, b) => a[0] < b[0] })
        sort(readInfos, key: { v: (Int64, ReadFileParam) => v[0] })

        // Check for both types of redundancy: read-after-write and overlapping reads
        for (i in 0..readInfos.size) {
            let (index1, info1) = readInfos[i]
            let start1 = info1.startLine
            let end1 = info1.endLine

            // Check Type 1: Read invalidated by subsequent file edit
            if (let Some(editIndex) <- fileEditIndexes.get(filePath)) {
                // This read is invalidated by a later edit
                if (index1 < editIndex) {
                    // Set the current read obsolete.
                    // NOTE that if this is a batch read, all reads are obsolete
                    markObsolete(steps, index1)
                    LogUtils.debug("Marked read as obsolete (invalidated by file edit). ${info1.toJsonValue().toString()}")
                    continue  // Skip further checks, already marked as redundant
                }
            }

            // Check Type 2: Read range contained by subsequent read
            for (j in (i + 1)..readInfos.size) {
                let (index2, info2) = readInfos[j]
                let start2 = info2.startLine
                let end2 = info2.endLine

                // If read at index2 contains read at index1, mark index1 as redundant
                if (isRangeContained(start1, end1, start2, end2)) {
                    markObsolete(steps, index1)
                    LogUtils.debug("Marked read as obsolete (contained by later read). ${info1.toJsonValue().toString()}")
                    break  // Found containment relationship, no need to check further reads
                }
            }
        }
    }
}

private func markObsolete(steps: ArrayList<StepMessage>, index: Int64): Unit {
    steps[index].setObsolete()
    // Mark the next step (i.e., the result of the read) as obsolete if it exists
    if (index + 1 < steps.size) {
        steps[index + 1].setObsolete()
    }
}

/**
 * Checks if range1 is contained within range2.
 * Range containment rules:
 * - start2 <= start1 (range2 starts at or before range1)
 * - end2 >= end1 (range2 ends at or after range1)
 * - None values represent: start = 1, end = ∞ (entire file)
 *
 * Returns true if range1 is completely contained within range2
 */
private func isRangeContained(start1: Option<Int64>, end1: Option<Int64>, start2: Option<Int64>, end2: Option<Int64>): Bool {
    // Default values: None means entire file (start=1, end=∞)
    let s1 = start1 ?? 1  // Default to line 1
    let e1 = end1 ?? Int64.Max  // Default to end of file
    let s2 = start2 ?? 1
    let e2 = end2 ?? Int64.Max

    return s2 <= s1 && e2 >= e1
}