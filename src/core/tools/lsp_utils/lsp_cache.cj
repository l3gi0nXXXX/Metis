package metis.core.tools.lsp_utils

import metis.lsp.*

import std.collection.{HashMap, ArrayList}
import std.fs.{Path, exists, File, FileInfo}
import std.time.DateTime

/**
 * Cache entry for LSP results with file modification time tracking
 */
public struct LSPCacheEntry<T> {
    public let result: T
    public let cachedAt: DateTime

    public init(result: T) {
        this.result = result
        this.cachedAt = DateTime.now()
    }

    /**
     * Check if a cache entry has expired based on TTL
     */
    public func isExpired(TTL: Duration): Bool {
        return (DateTime.now() - cachedAt) > TTL
    }
}

/**
 * LSP result cache with file modification time validation
 * Provides caching for different types of LSP operations
 */
public class LSPCache {
    private let symbolsCache = HashMap<String, LSPCacheEntry<Array<DocumentSymbol>>>()
    private let definitionCache = HashMap<String, LSPCacheEntry<DefinitionResult>>()
    private let referenceCache = HashMap<String, LSPCacheEntry<ReferenceResult>>()

    // Cache TTL in seconds - cache entries expire after this duration
    private let cacheTTL: Duration = Duration.minute * 30

    /**
     * Check if the cache entry is still valid based on file modification time
     */
    private func isCacheEntryValid<T>(filePath: Path, entry: LSPCacheEntry<T>): Bool {
        if (!exists(filePath)) {
            return false
        }

        try {
            // Check if file modification time is before or equal to cache timestamp
            return FileInfo(filePath).lastModificationTime <= entry.cachedAt
        } catch (_: Exception) {
            return false
        }
    }

    private func checkCacheStatus<T>(filePath: Path, entry: LSPCacheEntry<T>): Bool {
        let status = this.isCacheEntryValid(filePath, entry) && !entry.isExpired(this.cacheTTL)
        if (!status) {
            this.invalidateFile(filePath)
        }
        return status
    }

    /**
     * Generate a cache key for a file
     */
    private func getCacheKey(filePath: Path): String {
        return filePath.toString()
    }

    /**
     * Generate a cache key for position-based operations (definition, references)
     */
    private func getPositionCacheKey(filePath: Path, line: Int64, column: Int64): String {
        return "${filePath.toString()}:${line}:${column}"
    }

    /**
     * Get cached document symbols for a file
     * @return cached symbols if valid, None if cache miss or invalid
     */
    public func getCachedSymbols(filePath: Path): Option<Array<DocumentSymbol>> {
        let key = this.getCacheKey(filePath)
        if (!this.symbolsCache.contains(key)) {
            return None
        }

        let entry = this.symbolsCache[key]
        if (!this.checkCacheStatus(filePath, entry)) {
            return None
        } else {
            return Some(entry.result)
        }
    }

    /**
     * Cache document symbols for a file
     */
    public func cacheSymbols(filePath: Path, symbols: Array<DocumentSymbol>): Unit {
        try {
            let key = this.getCacheKey(filePath)
            this.symbolsCache[key] = LSPCacheEntry(symbols)
        } catch (_: Exception) {
            // If we can't get modification time, don't cache
        }
    }

    /**
     * Get cached definition result for a position in a file
     */
    public func getCachedDefinition(filePath: Path, line: Int64, column: Int64): Option<DefinitionResult> {
        let key = this.getPositionCacheKey(filePath, line, column)
        if (!this.definitionCache.contains(key)) {
            return None
        }

        let entry = this.definitionCache[key]
        if (!this.checkCacheStatus(filePath, entry)) {
            return None
        } else {
            return Some(entry.result)
        }
    }

    /**
     * Cache definition result for a position in a file
     */
    public func cacheDefinition(filePath: Path, line: Int64, column: Int64, result: DefinitionResult): Unit {
        try {
            let key = this.getPositionCacheKey(filePath, line, column)
            this.definitionCache[key] = LSPCacheEntry(result)
        } catch (_: Exception) {
            // If we can't get modification time, don't cache
        }
    }

    /**
     * Get cached reference result for a position in a file
     */
    public func getCachedReferences(filePath: Path, line: Int64, column: Int64): Option<ReferenceResult> {
        let key = this.getPositionCacheKey(filePath, line, column)
        if (!this.referenceCache.contains(key)) {
            return None
        }

        let entry = this.referenceCache[key]
        if (!this.checkCacheStatus(filePath, entry)) {
            this.invalidateFile(filePath)
            return None
        } else {
            return Some(entry.result)
        }
    }

    /**
     * Cache reference result for a position in a file
     */
    public func cacheReferences(filePath: Path, line: Int64, column: Int64, result: ReferenceResult): Unit {
        try {
            let key = this.getPositionCacheKey(filePath, line, column)
            this.referenceCache[key] = LSPCacheEntry(result)
        } catch (_: Exception) {
            // If we can't get modification time, don't cache
        }
    }

    /**
     * Invalidate all cache entries for a specific file
     * This should be called when the file is known to have been modified
     */
    public func invalidateFile(filePath: Path): Unit {
        let fileKey = this.getCacheKey(filePath)
        this.symbolsCache.remove(fileKey)

        // Remove position-based caches for this file
        let keysToRemove = ArrayList<String>()
        for ((key, _) in this.definitionCache) {
            if (key.startsWith(fileKey)) {
                keysToRemove.add(key)
            }
        }
        this.definitionCache.remove(all: keysToRemove)

        keysToRemove.clear()
        for ((key, _) in this.referenceCache) {
            if (key.startsWith(fileKey)) {
                keysToRemove.add(key)
            }
        }
        this.referenceCache.remove(all: keysToRemove)
    }

    /**
     * Clear all cached entries
     */
    public func clearAll(): Unit {
        this.symbolsCache.clear()
        this.definitionCache.clear()
        this.referenceCache.clear()
    }

    /**
     * Get cache statistics for debugging
     */
    public func getCacheStats(): (Int64, Int64, Int64) {
        return (this.symbolsCache.size, this.definitionCache.size, this.referenceCache.size)
    }
}