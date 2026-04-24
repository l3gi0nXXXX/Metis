"""
Core data models for the Graph RAG system.
"""
from dataclasses import dataclass
from typing import List, Optional
from enum import Enum


class ElementType(Enum):
    """Types of code elements that can be extracted."""
    FUNCTION = "function"
    CLASS = "class"
    STRUCT = "struct"
    INTERFACE = "interface"
    ENUM = "enum"


class ReferenceType(Enum):
    """Types of references between code elements."""
    CALLS = "calls"
    MENTIONS = "mentions"
    TYPE_REFERENCE = "type_reference"  # For parameter types and return types


@dataclass
class ChunkMetadata:
    """Additional metadata for a chunk."""
    code_elements: List[str]  # Names of extracted code elements
    language: str = "cangjie"
    section_title: Optional[str] = None  # Markdown header if applicable


@dataclass
class Chunk:
    """A chunk of documentation content."""
    id: str
    content: str
    file_path: str
    start_line: int
    end_line: int
    chunk_type: str  # "TEXT", "CODE", "MIXED"
    metadata: ChunkMetadata


@dataclass
class CodeElement:
    """A code element extracted from documentation."""
    name: str
    element_type: ElementType
    signature: Optional[str]  # Full signature for functions
    source_chunk: str
    line_number: Optional[int] = None


@dataclass
class Reference:
    """A reference from one chunk to a code element."""
    source_chunk: str
    target_element: str
    reference_type: ReferenceType
    receiver: Optional[str] = None  # For method calls like "obj.method()"
    confidence: float = 1.0


@dataclass
class ChunkResult:
    """Result from vector search with similarity score."""
    id: str
    content: str
    score: float
    metadata: ChunkMetadata


@dataclass
class RetrievalConfig:
    """Configuration for the retrieval system."""
    initial_k: int = 5  # Initial semantic search results
    max_graph_distance: int = 2  # Maximum hops in graph traversal
    relevance_threshold: float = 0.3  # Minimum score for graph expansion
    max_total_chunks: int = 20  # Maximum final results
    rerank_by_graph: bool = True  # Re-rank using graph centrality


@dataclass
class GraphEdge:
    """An edge in the code graph."""
    source: str
    target: str
    element: str
    weight: float
    reference_type: ReferenceType


@dataclass
class ChunkNode:
    """A node in the code graph representing a chunk."""
    chunk_id: str
    code_elements: List[str]
    centrality_score: float = 0.0