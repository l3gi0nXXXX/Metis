#!/usr/bin/env python3
"""
Main interface for the Graph RAG system.

This script provides a command-line interface to build indices and query
the Cangjie documentation using the Graph RAG approach.
"""

import argparse
import json
import sys
from pathlib import Path
from typing import List, Optional

from src import (
    GraphRAGRetriever,
    MilvusVectorStore,
    RetrievalConfig,
    DirectoryProcessor,
    MarkdownChunker,
    GraphBuilder,
    CangjieCodeElementExtractor
)


def build_index(docs_path: str = None,
                jsonl_path: str = None,
                db_path: str = "./milvus_cangjie_docs.db",
                embedding_model_path: str = "./model/Conan-embedding-v1",
                max_chunk_size: int = 1000,
                graph_file: str = None) -> None:
    """Build the Graph RAG index from documentation files."""

    print("=" * 80)
    print("🚀 STARTING GRAPH RAG INDEX CONSTRUCTION")
    print("=" * 80)
    if docs_path:
        print(f"📁 Markdown directory: {docs_path}")
    if jsonl_path:
        print(f"📄 JSONL file: {jsonl_path}")
    print(f"💾 Database path: {db_path}")
    print(f"🧠 Embedding model: {embedding_model_path}")
    print(f"📏 Max chunk size: {max_chunk_size}")
    print()

    # Initialize components
    print("🔧 STEP 1: Initializing components...")
    
    # Extract collection name from db path
    db_name = Path(db_path).stem
    if db_name.startswith('milvus_'):
        collection_name = db_name[7:]  # Remove 'milvus_' prefix
    else:
        collection_name = db_name
    print(f"🗄️  Collection name: {collection_name}")

    vector_store = MilvusVectorStore(
        db_path=db_path,
        collection_name=collection_name,
        embedding_model_path=embedding_model_path
    )

    # Import hybrid processor
    from src.jsonl_processor import HybridProcessor

    hybrid_processor = HybridProcessor()
    extractor = CangjieCodeElementExtractor()
    graph_builder = GraphBuilder(extractor)
    print("✅ Components initialized successfully")
    print()

    # Process documents from multiple sources
    print("📚 STEP 2: Processing documents from all sources...")
    chunks, parent_relationships = hybrid_processor.process_hybrid_sources(
        markdown_dir=docs_path,
        jsonl_file=jsonl_path
    )

    if not chunks:
        raise ValueError(f"No documents found in provided sources")
    print()

    # Store in vector database
    print("💾 STEP 3: Storing chunks in vector database...")
    vector_store.store_chunks(chunks)
    print()

    # Build and save knowledge graph
    print("🕸️  STEP 4: Building and saving knowledge graph...")
    # Always build and save graph since it's expensive to build
    graph = graph_builder.build_and_save_graph(chunks, graph_file, parent_relationships)
    print()

    # Print final statistics
    print("📊 FINAL STATISTICS")
    print("=" * 50)
    stats = graph.get_graph_statistics()
    total_chunks = len(chunks)
    total_elements = sum(len(chunk.metadata.code_elements) for chunk in chunks)

    print(f"✨ INDEX CONSTRUCTION COMPLETED SUCCESSFULLY!")
    print(f"📄 Total chunks: {total_chunks}")
    print(f"🔧 Total code elements: {total_elements}")
    print(f"🕸️  Graph nodes: {stats['num_nodes']}")
    print(f"🔗 Graph edges: {stats['num_edges']}")
    print(f"🏝️  Connected components: {stats['num_connected_components']}")

    if 'most_central_chunks' in stats:
        print("\n🌟 Most central chunks (highest importance):")
        for i, (chunk_id, score) in enumerate(stats['most_central_chunks'], 1):
            print(f"  {i}. {chunk_id[:8]}... (score: {score:.3f})")

    print("=" * 80)
    print("🎉 Graph RAG index is ready for queries!")
    print("=" * 80)


def initialize_retrieval_system(db_path: str,
                              embed_model_path: str,
                              graph_file: str,
                              silent: bool = False) -> GraphRAGRetriever:
    """Initialize vector store, graph, and retriever with common logic."""
    from pathlib import Path

    # Check if database file exists
    if not Path(db_path).exists():
        error_msg = f"❌ Database file not found: {db_path}"
        if not silent:
            print(error_msg)
            print("💡 Tip: Run 'build' command first to create the database")
        raise FileNotFoundError(error_msg)

    # Check if embedding model exists
    if not Path(embed_model_path).exists():
        error_msg = f"❌ Embedding model not found: {embed_model_path}"
        if not silent:
            print(error_msg)
        raise FileNotFoundError(error_msg)

    # Extract collection name from db path
    db_name = Path(db_path).stem
    if db_name.startswith('milvus_'):
        collection_name = db_name[7:]  # Remove 'milvus_' prefix
    else:
        collection_name = db_name
    
    if not silent:
        print(f"✅ Database file found: {db_path}")
        print(f"✅ Embedding model found: {embed_model_path}")
    
    # Initialize vector store
    vector_store = MilvusVectorStore(
        db_path=db_path,
        collection_name=collection_name,
        embedding_model_path=embed_model_path
    )

    # Load graph if file exists, otherwise use empty graph
    if Path(graph_file).exists():
        from src.graph import GraphBuilder
        graph = GraphBuilder.load_graph(graph_file, silent=silent)
        if not silent:
            print("✅ Graph loaded for enhanced retrieval")
    else:
        from src.graph import CodeGraph
        graph = CodeGraph()
        if not silent:
            print(f"⚠️  Graph file {graph_file} not found - using semantic search only")
            print("💡 Tip: Run 'build' command first to create the graph file")

    # Create and return retriever
    return GraphRAGRetriever(vector_store, graph)


def query_docs(query: str,
               retriever: GraphRAGRetriever,
               config: Optional[RetrievalConfig] = None) -> List:
    """Query the documentation using the Graph RAG system."""

    if config is None:
        config = RetrievalConfig()

    print(f"Querying: {query}")
    print(f"Config: initial_k={config.initial_k}, max_distance={config.max_graph_distance}")

    results = retriever.retrieve(query, config)

    print(f"\nFound {len(results)} relevant chunks:")
    print("=" * 80)

    formatted_results = []
    for i, result in enumerate(results, 1):
        print(f"\n[{i}] Score: {result.score:.3f}")
        print(f"File: {Path(result.metadata.code_elements[0] if result.metadata.code_elements else 'unknown').name}")
        print(f"Code Elements: {', '.join(result.metadata.code_elements[:5])}")
        if result.metadata.section_title:
            print(f"Section: {result.metadata.section_title}")

        # Show content preview
        content_preview = result.content[:300] + "..." if len(result.content) > 300 else result.content
        print(f"Content: {content_preview}")
        print("-" * 40)

        formatted_results.append({
            'rank': i,
            'score': result.score,
            'content': result.content,
            'code_elements': result.metadata.code_elements,
            'section_title': result.metadata.section_title
        })

    return formatted_results


def interactive_mode(retriever: GraphRAGRetriever):
    """Run in interactive query mode."""

    print("\n🔍 Graph RAG Interactive Mode")
    print("Type your queries about Cangjie documentation.")
    print("Commands: /config, /stats, /quit")
    print("=" * 50)

    config = RetrievalConfig()

    while True:
        try:
            query = input("\n💬 Query: ").strip()

            if not query:
                continue

            if query == "/quit":
                break
            elif query == "/stats":
                stats = retriever.get_statistics()
                print(json.dumps(stats, indent=2))
                continue
            elif query.startswith("/config"):
                # Allow basic config changes
                parts = query.split()
                if len(parts) >= 3:
                    param, value = parts[1], parts[2]
                    if param == "initial_k":
                        config.initial_k = int(value)
                        print(f"Set initial_k to {value}")
                    elif param == "max_distance":
                        config.max_graph_distance = int(value)
                        print(f"Set max_distance to {value}")
                    elif param == "max_results":
                        config.max_total_chunks = int(value)
                        print(f"Set max_results to {value}")
                else:
                    print(f"Current config: {config}")
                continue

            # Perform query
            query_docs(query, retriever, config)

        except KeyboardInterrupt:
            print("\n👋 Goodbye!")
            break
        except Exception as e:
            print(f"❌ Error: {e}")


def main():
    """Main CLI interface."""

    parser = argparse.ArgumentParser(description="Graph RAG for Cangjie Documentation")

    subparsers = parser.add_subparsers(dest='command', help='Available commands')

    # Build command
    build_parser = subparsers.add_parser('build', help='Build the search index')
    build_parser.add_argument('--docs', help='Path to markdown documentation directory')
    build_parser.add_argument('--jsonl', help='Path to JSONL file with DocumentModel schema')
    build_parser.add_argument('--db', default='./milvus_cangjie_docs.db', help='Milvus database path')
    build_parser.add_argument('--embed-model', default='./model/Conan-embedding-v1', help='Embedding model path')
    build_parser.add_argument('--chunk-size', type=int, default=1000, help='Maximum chunk size')
    build_parser.add_argument('--save-graph', default='graph.pkl', help='Save graph to file (default: graph.pkl)')

    # Query command
    query_parser = subparsers.add_parser('query', help='Query the documentation')
    query_parser.add_argument('query', help='Query string')
    query_parser.add_argument('--db', default='./milvus_cangjie_docs.db', help='Milvus database path')
    query_parser.add_argument('--embed-model', default='./model/Conan-embedding-v1', help='Embedding model path')
    query_parser.add_argument('--load-graph', default='graph.pkl', help='Load graph from file (default: graph.pkl)')
    query_parser.add_argument('--initial-k', type=int, default=5, help='Initial semantic search results')
    query_parser.add_argument('--max-distance', type=int, default=2, help='Maximum graph traversal distance')
    query_parser.add_argument('--max-results', type=int, default=10, help='Maximum final results')
    query_parser.add_argument('--output', help='Output file for results (JSON)')

    # Interactive command
    interactive_parser = subparsers.add_parser('interactive', help='Start interactive mode')
    interactive_parser.add_argument('--db', default='./milvus_cangjie_docs.db', help='Milvus database path')
    interactive_parser.add_argument('--embed-model', default='./model/Conan-embedding-v1', help='Embedding model path')
    interactive_parser.add_argument('--load-graph', default='graph.pkl', help='Load graph from file (default: graph.pkl)')


    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return

    try:
        if args.command == 'build':
            if not args.docs and not args.jsonl:
                print("❌ Error: Must provide either --docs or --jsonl (or both)")
                return

            build_index(
                docs_path=args.docs,
                jsonl_path=args.jsonl,
                db_path=args.db,
                embedding_model_path=args.embed_model,
                max_chunk_size=args.chunk_size,
                graph_file=args.save_graph
            )

        elif args.command == 'query':
            # Initialize retrieval system
            retriever = initialize_retrieval_system(
                args.db,
                args.embed_model,
                args.load_graph
            )

            config = RetrievalConfig(
                initial_k=args.initial_k,
                max_graph_distance=args.max_distance,
                max_total_chunks=args.max_results
            )

            # Perform the query
            results = query_docs(args.query, retriever, config)

            # Save to output file if specified
            if args.output:
                with open(args.output, 'w') as f:
                    json.dump(results, f, indent=2)
                print(f"📁 Results saved to: {args.output}")

        elif args.command == 'interactive':
            # Initialize retrieval system
            retriever = initialize_retrieval_system(
                args.db,
                args.embed_model,
                args.load_graph
            )

            interactive_mode(retriever)


    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()