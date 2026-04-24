#!/usr/bin/env python3
"""
MCP Server for Cangjie Graph RAG.

This is a standalone MCP server that can be launched directly by MCP clients.
It loads the pre-built vector database and graph files to provide documentation
search capabilities via the retrieve_cangjie_docs tool.
"""

import argparse
import asyncio
import sys
from pathlib import Path

# FastMCP imports
from fastmcp import FastMCP

# Graph RAG imports
from src.graph import GraphBuilder, CodeGraph
from src.vector_store import MilvusVectorStore
from src.retriever import GraphRAGRetriever, RetrievalConfig
from main import initialize_retrieval_system


def format_results(query: str, results) -> str:
    """Format retrieval results for MCP response."""

    response_parts = [
        f"# Cangjie Documentation Search Results",
        f"",
        f"**Query:** {query}",
        f"**Found:** {len(results)} relevant documentation chunks",
        f"",
        "---",
        ""
    ]

    for i, result in enumerate(results, 1):
        # Extract file info from metadata
        file_info = ""
        if result.metadata.code_elements:
            file_info = f"({result.metadata.code_elements[0]})"

        response_parts.extend([
            f"## Result {i}",
            ""
        ])

        # Add section title if available
        if result.metadata.section_title:
            response_parts.extend([
                f"**Section:** {result.metadata.section_title}",
                ""
            ])

        # Add code elements if available
        if result.metadata.code_elements:
            elements_str = ", ".join(result.metadata.code_elements[:5])
            if len(result.metadata.code_elements) > 5:
                elements_str += f" (+ {len(result.metadata.code_elements) - 5} more)"
            response_parts.extend([
                f"**Code Elements:** {elements_str}",
                ""
            ])

        # Add content
        response_parts.extend([
            "**Content:**",
            "",
            result.content,
            "",
            "---",
            ""
        ])

    return "\n".join(response_parts)

# Initialize FastMCP
mcp = FastMCP("Cangjie Graph RAG")

retriever = None

@mcp.tool()
def retrieve_cangjie_docs(query: str, max_total_chunks: int = 10) -> str:
    """
    Retrieve relevant Cangjie documentation using Graph RAG.

    Searches through code examples, API docs, and tutorials using both semantic
    search and knowledge graph relationships.

    Args:
        query: The search query about Cangjie programming language
                (e.g., 'how to define functions', 'class inheritance syntax', 'array operations')
        max_total_chunks: Maximum number of documentation chunks to return (default: 10, max: 50)

    Returns:
        Formatted documentation results with relevance scores and code elements
    """
    if not query.strip():
        return "Error: Query parameter is required and cannot be empty."

    # Validate max_total_chunks
    max_total_chunks = max(1, min(50, max_total_chunks))

    try:
        # Configure retrieval
        config = RetrievalConfig(
            initial_k=min(5, max_total_chunks),
            max_graph_distance=2,
            max_total_chunks=max_total_chunks,
            relevance_threshold=0.3,
            rerank_by_graph=True
        )

        # Perform retrieval
        results = retriever.retrieve(query, config)

        if not results:
            return f"No relevant documentation found for query: '{query}'"

        # Format results
        return format_results(query, results)

    except Exception as e:
        return f"Error retrieving Cangjie documentation: {str(e)}"


def main():
    """Main entry point for the MCP server."""

    # Parse command line arguments
    parser = argparse.ArgumentParser(description="Cangjie Graph RAG MCP Server")
    parser.add_argument('--db', default='./milvus_cangjie_docs.db',
                       help='Milvus database path (default: ./milvus_cangjie_docs.db)')
    parser.add_argument('--embed-model', default='./model/Conan-embedding-v1',
                       help='Embedding model path (default: ./model/Conan-embedding-v1)')
    parser.add_argument('--load-graph', default='graph.pkl',
                       help='Load graph from file (default: graph.pkl)')

    args = parser.parse_args()

    try:
        # Create retriever
        global retriever
        retriever = initialize_retrieval_system(
            args.db,
            args.embed_model,
            args.load_graph,
            silent=True
        )

        # Start MCP server
        # asyncio.run(mcp.run())
        mcp.run(transport='sse', port=8787)
        # asyncio.run(mcp.run(transport='sse', port=8787))

    except ImportError:
        # Dependencies not available - exit silently for MCP
        sys.exit(1)
    except KeyboardInterrupt:
        # Silent exit for MCP
        pass
    except Exception:
        # Any other error - exit silently for MCP
        sys.exit(1)


if __name__ == "__main__":
    main()