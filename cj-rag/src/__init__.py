"""
Graph RAG for Cangjie Code Documentation

A Graph-based Retrieval-Augmented Generation system for code documentation
that combines semantic similarity search with graph traversal based on code relationships.
"""

from .models import (
    Chunk, ChunkMetadata, CodeElement, Reference, ChunkResult, 
    RetrievalConfig, ElementType, ReferenceType
)
from .chunker import MarkdownChunker, DirectoryProcessor
from .extractor import CangjieCodeElementExtractor, CangjiePatterns
from .vector_store import MilvusVectorStore
from .graph import CodeGraph, GraphBuilder
from .retriever import GraphRAGRetriever, QueryAnalyzer, ResultRanker
from .jsonl_processor import DocumentModel, JSONLProcessor, HybridProcessor

__version__ = "0.1.0"
__all__ = [
    # Core models
    "Chunk", "ChunkMetadata", "CodeElement", "Reference", "ChunkResult",
    "RetrievalConfig", "ElementType", "ReferenceType",
    
    # Processing components
    "MarkdownChunker", "DirectoryProcessor",
    "CangjieCodeElementExtractor", "CangjiePatterns",
    
    # JSONL support
    "DocumentModel", "JSONLProcessor", "HybridProcessor",
    
    # Storage and graph
    "MilvusVectorStore", "CodeGraph", "GraphBuilder",
    
    # Retrieval system
    "GraphRAGRetriever", "QueryAnalyzer", "ResultRanker"
]