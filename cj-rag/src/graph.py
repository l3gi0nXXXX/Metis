"""
Graph construction and traversal system for connecting related chunks.
"""
import networkx as nx
import pickle
import json
from pathlib import Path
from typing import List, Dict, Set, Tuple, Optional
from collections import defaultdict

from .models import (
    Chunk, CodeElement, Reference, GraphEdge, ChunkNode, 
    ReferenceType, ElementType
)
from .extractor import CangjieCodeElementExtractor


class CodeGraph:
    """Graph structure for representing relationships between code chunks."""
    
    def __init__(self):
        self.graph = nx.DiGraph()  # Directed graph for code relationships
        self.element_index: Dict[str, List[str]] = defaultdict(list)  # element_name -> chunk_ids
        self.chunk_elements: Dict[str, List[str]] = {}  # chunk_id -> element_names
        self.chunk_metadata: Dict[str, ChunkNode] = {}  # chunk_id -> ChunkNode
    
    def add_chunk(self, chunk: Chunk, elements: List[CodeElement]) -> None:
        """Add a chunk and its code elements to the graph."""
        # Create node for the chunk
        element_names = [elem.name for elem in elements]
        
        chunk_node = ChunkNode(
            chunk_id=chunk.id,
            code_elements=element_names,
            centrality_score=0.0
        )
        
        self.chunk_metadata[chunk.id] = chunk_node
        self.chunk_elements[chunk.id] = element_names
        
        # Add node to graph
        self.graph.add_node(chunk.id, **{
            'chunk_type': chunk.chunk_type,
            'file_path': chunk.file_path,
            'elements': element_names
        })
        
        # Update element index
        for element in elements:
            self.element_index[element.name].append(chunk.id)
    
    def add_reference_edge(self, source_chunk: str, target_chunk: str, 
                          element: str, weight: float, 
                          reference_type: ReferenceType = ReferenceType.CALLS) -> None:
        """Add a reference edge between chunks."""
        if source_chunk == target_chunk:
            return  # Skip self-references
        
        # Add edge to graph
        self.graph.add_edge(source_chunk, target_chunk, **{
            'element': element,
            'weight': weight,
            'reference_type': reference_type.value
        })
    
    def build_references(self, chunks: List[Chunk], 
                        extractor: CangjieCodeElementExtractor) -> None:
        """Build reference edges between chunks based on code elements."""
        chunk_dict = {chunk.id: chunk for chunk in chunks}
        total_references = 0
        edges_created = 0
        
        for i, chunk in enumerate(chunks, 1):
            if i % 50 == 0 or i == len(chunks):
                print(f"  📊 Progress: {i}/{len(chunks)} chunks processed, {edges_created} edges created")
            
            references = extractor.extract_references(chunk)
            total_references += len(references)
            
            for ref in references:
                # Find chunks that define the target element
                target_chunks = self.element_index.get(ref.target_element, [])
                
                for target_chunk_id in target_chunks:
                    if target_chunk_id != chunk.id:  # Don't connect to self
                        weight = self._calculate_edge_weight(
                            chunk_dict[chunk.id], 
                            chunk_dict[target_chunk_id],
                            ref
                        )
                        
                        self.add_reference_edge(
                            chunk.id, 
                            target_chunk_id, 
                            ref.target_element,
                            weight,
                            ref.reference_type
                        )
                        edges_created += 1
        
        # Count different types of references
        call_refs = sum(1 for chunk in chunks for ref in extractor.extract_references(chunk) 
                       if ref.reference_type.value == "calls")
        type_refs = sum(1 for chunk in chunks for ref in extractor.extract_references(chunk) 
                       if ref.reference_type.value == "type_reference")
        mention_refs = total_references - call_refs - type_refs
        
        print(f"\n  ✅ Reference Analysis Complete:")
        print(f"     📊 Total references found: {total_references}")
        print(f"     🔧 Function calls: {call_refs}")
        print(f"     📝 Type references: {type_refs}")
        print(f"     💬 Other mentions: {mention_refs}")
        print(f"     🔗 Graph edges created: {edges_created}")
        print()
    
    def _calculate_edge_weight(self, source_chunk: Chunk, target_chunk: Chunk, 
                              reference: Reference) -> float:
        """Calculate edge weight based on relationship strength."""
        base_weight = 0.5
        
        # Boost weight for function calls vs mentions vs type references
        if reference.reference_type == ReferenceType.CALLS:
            base_weight = 0.9
        elif reference.reference_type == ReferenceType.TYPE_REFERENCE:
            base_weight = 0.8  # High weight for type references as they indicate strong structural relationships
        elif reference.reference_type == ReferenceType.MENTIONS:
            base_weight = 0.6
        
        # Boost weight for same file
        if source_chunk.file_path == target_chunk.file_path:
            base_weight += 0.2
        
        # Boost weight for proximity in same file
        if (source_chunk.file_path == target_chunk.file_path and 
            abs(source_chunk.start_line - target_chunk.start_line) < 50):
            base_weight += 0.1
        
        # Apply confidence score
        base_weight *= reference.confidence
        
        return min(base_weight, 1.0)  # Cap at 1.0
    
    def get_neighbors(self, chunk_id: str, max_distance: int = 2, 
                     min_weight: float = 0.3) -> List[str]:
        """Get neighboring chunks within max_distance hops."""
        if chunk_id not in self.graph:
            return []
        
        neighbors = set()
        current_level = {chunk_id}
        
        for distance in range(1, max_distance + 1):
            next_level = set()
            
            for node in current_level:
                # Get outgoing edges (chunks this node references)
                for neighbor in self.graph.successors(node):
                    edge_data = self.graph.get_edge_data(node, neighbor)
                    if edge_data and edge_data.get('weight', 0) >= min_weight:
                        next_level.add(neighbor)
                        neighbors.add(neighbor)
                
                # Get incoming edges (chunks that reference this node)
                for neighbor in self.graph.predecessors(node):
                    edge_data = self.graph.get_edge_data(neighbor, node)
                    if edge_data and edge_data.get('weight', 0) >= min_weight:
                        next_level.add(neighbor)
                        neighbors.add(neighbor)
            
            current_level = next_level
            
            if not current_level:
                break
        
        return list(neighbors)
    
    def get_related_by_element(self, element_name: str, 
                              exclude_chunk: Optional[str] = None) -> List[str]:
        """Get all chunks that contain or reference a specific element."""
        related_chunks = self.element_index.get(element_name, [])
        
        if exclude_chunk:
            related_chunks = [chunk_id for chunk_id in related_chunks 
                            if chunk_id != exclude_chunk]
        
        return related_chunks
    
    def compute_centrality_scores(self) -> None:
        """Compute centrality scores for all chunks in the graph."""
        if not self.graph.nodes():
            return
        
        # Calculate PageRank centrality
        try:
            pagerank_scores = nx.pagerank(self.graph, weight='weight')
        except nx.PowerIterationFailedToConverge:
            # Fallback to degree centrality if PageRank fails
            pagerank_scores = nx.degree_centrality(self.graph)
        
        # Update chunk metadata with centrality scores
        for chunk_id, score in pagerank_scores.items():
            if chunk_id in self.chunk_metadata:
                self.chunk_metadata[chunk_id].centrality_score = score
    
    def get_subgraph_for_elements(self, element_names: List[str], 
                                 max_depth: int = 2) -> Set[str]:
        """Get subgraph containing chunks related to specific elements."""
        relevant_chunks = set()
        
        # Start with chunks that define the elements
        for element_name in element_names:
            relevant_chunks.update(self.element_index.get(element_name, []))
        
        # Expand to include related chunks
        expanded_chunks = set(relevant_chunks)
        for chunk_id in relevant_chunks:
            neighbors = self.get_neighbors(chunk_id, max_depth)
            expanded_chunks.update(neighbors)
        
        return expanded_chunks
    
    def get_shortest_path(self, source_chunk: str, target_chunk: str) -> List[str]:
        """Get shortest path between two chunks."""
        try:
            return nx.shortest_path(self.graph, source_chunk, target_chunk)
        except (nx.NetworkXNoPath, nx.NodeNotFound):
            return []
    
    def get_graph_statistics(self) -> Dict[str, any]:
        """Get basic statistics about the graph."""
        if not self.graph.nodes():
            return {
                'num_nodes': 0,
                'num_edges': 0,
                'avg_degree': 0,
                'num_connected_components': 0
            }
        
        return {
            'num_nodes': self.graph.number_of_nodes(),
            'num_edges': self.graph.number_of_edges(),
            'avg_degree': sum(dict(self.graph.degree()).values()) / self.graph.number_of_nodes(),
            'num_connected_components': nx.number_weakly_connected_components(self.graph),
            'most_central_chunks': self._get_most_central_chunks(5)
        }
    
    def _get_most_central_chunks(self, top_k: int = 5) -> List[Tuple[str, float]]:
        """Get the most central chunks by centrality score."""
        chunks_with_scores = [
            (chunk_id, node.centrality_score) 
            for chunk_id, node in self.chunk_metadata.items()
        ]
        
        chunks_with_scores.sort(key=lambda x: x[1], reverse=True)
        return chunks_with_scores[:top_k]
    
    def save_to_file(self, file_path: str) -> None:
        """Save the graph to a file."""
        file_path = Path(file_path)
        file_path.parent.mkdir(parents=True, exist_ok=True)
        
        print(f"\n💾 SAVING GRAPH TO: {file_path}")
        print("-" * 50)
        
        # Prepare data to save
        graph_data = {
            'graph': nx.node_link_data(self.graph),  # NetworkX graph as JSON-serializable format
            'element_index': dict(self.element_index),  # Convert defaultdict to regular dict
            'chunk_elements': self.chunk_elements,
            'chunk_metadata': {
                chunk_id: {
                    'chunk_id': node.chunk_id,
                    'code_elements': node.code_elements,
                    'centrality_score': node.centrality_score
                }
                for chunk_id, node in self.chunk_metadata.items()
            }
        }
        
        # Save to pickle file for Python objects
        with open(file_path, 'wb') as f:
            pickle.dump(graph_data, f)
        
        stats = self.get_graph_statistics()
        print(f"✅ GRAPH SAVED SUCCESSFULLY:")
        print(f"    📊 Nodes: {stats['num_nodes']}")
        print(f"    🔗 Edges: {stats['num_edges']}")
        print(f"    📁 File size: {file_path.stat().st_size / 1024:.1f} KB")
        print("-" * 50)
    
    @classmethod
    def load_from_file(cls, file_path: str, silent: bool = False) -> 'CodeGraph':
        """Load a graph from a file."""
        file_path = Path(file_path)
        
        if not file_path.exists():
            raise FileNotFoundError(f"Graph file not found: {file_path}")
        
        if not silent:
            print(f"\n📂 LOADING GRAPH FROM: {file_path}")
            print("-" * 50)
        
        # Load from pickle file
        with open(file_path, 'rb') as f:
            graph_data = pickle.load(f)
        
        # Create new CodeGraph instance
        code_graph = cls()
        
        # Restore NetworkX graph
        code_graph.graph = nx.node_link_graph(graph_data['graph'], edges="links")
        
        # Restore element index (convert back to defaultdict)
        code_graph.element_index = defaultdict(list)
        for element, chunk_ids in graph_data['element_index'].items():
            code_graph.element_index[element] = chunk_ids
        
        # Restore chunk elements
        code_graph.chunk_elements = graph_data['chunk_elements']
        
        # Restore chunk metadata (convert back to ChunkNode objects)
        code_graph.chunk_metadata = {}
        for chunk_id, metadata in graph_data['chunk_metadata'].items():
            code_graph.chunk_metadata[chunk_id] = ChunkNode(
                chunk_id=metadata['chunk_id'],
                code_elements=metadata['code_elements'],
                centrality_score=metadata['centrality_score']
            )
        
        if not silent:
            stats = code_graph.get_graph_statistics()
            print(f"✅ GRAPH LOADED SUCCESSFULLY:")
            print(f"    📊 Nodes: {stats['num_nodes']}")
            print(f"    🔗 Edges: {stats['num_edges']}")
            print(f"    📁 File size: {file_path.stat().st_size / 1024:.1f} KB")
            print("-" * 50)
        
        return code_graph
    
    def save_metadata_json(self, file_path: str) -> None:
        """Save graph metadata as human-readable JSON for inspection."""
        file_path = Path(file_path)
        file_path.parent.mkdir(parents=True, exist_ok=True)
        
        # Create human-readable metadata
        metadata = {
            'statistics': self.get_graph_statistics(),
            'nodes': [
                {
                    'chunk_id': chunk_id,
                    'code_elements': node.code_elements,
                    'centrality_score': round(node.centrality_score, 4)
                }
                for chunk_id, node in self.chunk_metadata.items()
            ],
            'edges': [
                {
                    'source': source,
                    'target': target,
                    'element': data.get('element', ''),
                    'weight': data.get('weight', 0),
                    'reference_type': data.get('reference_type', '')
                }
                for source, target, data in self.graph.edges(data=True)
            ],
            'element_index': {
                element: chunk_ids 
                for element, chunk_ids in self.element_index.items()
            }
        }
        
        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(metadata, f, indent=2, ensure_ascii=False)
        
        print(f"📋 Graph metadata saved to: {file_path}")


class GraphBuilder:
    """Builder class for constructing code graphs from chunks."""
    
    def __init__(self, extractor: Optional[CangjieCodeElementExtractor] = None):
        self.extractor = extractor or CangjieCodeElementExtractor()
    
    def build_graph(self, chunks: List[Chunk], parent_relationships: Optional[Dict[str, List[str]]] = None) -> CodeGraph:
        """Build a complete graph from a list of chunks."""
        print(f"\n🕸️  BUILDING KNOWLEDGE GRAPH FROM {len(chunks)} CHUNKS")
        print("=" * 60)
        graph = CodeGraph()
        
        # First pass: add all chunks and their elements
        print(f"\n🏗️  PHASE 1: EXTRACTING CODE ELEMENTS")
        print("-" * 40)
        total_elements = 0
        for i, chunk in enumerate(chunks, 1):
            if i % 20 == 0 or i == len(chunks):
                print(f"  📊 Progress: {i}/{len(chunks)} chunks processed")
            elements = self.extractor.extract_elements(chunk)
            total_elements += len(elements)
            graph.add_chunk(chunk, elements)
        
        print(f"\n  ✅ PHASE 1 COMPLETE: {total_elements} code elements extracted from {len(chunks)} chunks")
        
        # Second pass: build reference relationships
        print(f"\n🔗 PHASE 2: BUILDING REFERENCE RELATIONSHIPS")
        print("-" * 40)
        graph.build_references(chunks, self.extractor)
        
        # Third pass: add parent-child relationships from JSONL if available
        if parent_relationships:
            print(f"\n👨‍👩‍👧‍👦 PHASE 2.5: ADDING PARENT-CHILD RELATIONSHIPS")
            print("-" * 40)
            self._add_parent_relationships(graph, parent_relationships)
        
        # Compute centrality scores
        print(f"\n📈 PHASE 3: COMPUTING CENTRALITY SCORES")
        print("-" * 40)
        graph.compute_centrality_scores()
        
        # Print graph statistics
        stats = graph.get_graph_statistics()
        print(f"\n🎉 GRAPH CONSTRUCTION COMPLETED!")
        print("=" * 60)
        print(f"   📊 Nodes: {stats['num_nodes']}")
        print(f"   🔗 Edges: {stats['num_edges']}")
        print(f"   🎯 Average degree: {stats['avg_degree']:.2f}")
        print(f"   🏝️  Connected components: {stats['num_connected_components']}")
        print("=" * 60)
        
        return graph
    
    def _add_parent_relationships(self, graph: CodeGraph, parent_relationships: Dict[str, List[str]]) -> None:
        """Add parent-child relationships to the graph."""
        from .models import ReferenceType
        
        edges_added = 0
        for child_chunk, parent_chunks in parent_relationships.items():
            for parent_chunk in parent_chunks:
                # Add bidirectional edges with high weight for parent-child relationships
                graph.add_reference_edge(
                    source_chunk=child_chunk,
                    target_chunk=parent_chunk,
                    element="parent_relationship",
                    weight=0.85,  # High weight for structural relationships
                    reference_type=ReferenceType.MENTIONS
                )
                
                graph.add_reference_edge(
                    source_chunk=parent_chunk,
                    target_chunk=child_chunk,
                    element="child_relationship", 
                    weight=0.85,
                    reference_type=ReferenceType.MENTIONS
                )
                edges_added += 2
        
        print(f"\n  ✅ PHASE 2.5 COMPLETE: {edges_added} parent-child edges added from JSONL relationships")
    
    def update_graph(self, graph: CodeGraph, new_chunks: List[Chunk], 
                    removed_chunk_ids: List[str] = None) -> CodeGraph:
        """Update an existing graph with new chunks."""
        # Remove old chunks
        if removed_chunk_ids:
            for chunk_id in removed_chunk_ids:
                if chunk_id in graph.graph:
                    # Remove from element index
                    if chunk_id in graph.chunk_elements:
                        for element in graph.chunk_elements[chunk_id]:
                            if element in graph.element_index:
                                graph.element_index[element] = [
                                    cid for cid in graph.element_index[element] 
                                    if cid != chunk_id
                                ]
                    
                    # Remove from graph
                    graph.graph.remove_node(chunk_id)
                    
                    # Clean up metadata
                    graph.chunk_elements.pop(chunk_id, None)
                    graph.chunk_metadata.pop(chunk_id, None)
        
        # Add new chunks
        all_chunks = new_chunks.copy()
        
        # Get existing chunks for reference building
        for chunk_id in graph.chunk_metadata:
            # We need chunk objects for reference building, but we only have IDs
            # This is a limitation - in practice, you'd want to store chunk objects
            pass
        
        # Add new chunks and elements
        for chunk in new_chunks:
            elements = self.extractor.extract_elements(chunk)
            graph.add_chunk(chunk, elements)
        
        # Rebuild references for new chunks
        graph.build_references(new_chunks, self.extractor)
        
        # Recompute centrality scores
        graph.compute_centrality_scores()
        
        return graph
    
    def build_and_save_graph(self, chunks: List[Chunk], graph_file: str, 
                           parent_relationships: Optional[Dict[str, List[str]]] = None,
                           save_metadata: bool = True) -> CodeGraph:
        """Build graph and automatically save it to file."""
        # Build the graph
        graph = self.build_graph(chunks, parent_relationships)
        
        # Save the graph
        graph.save_to_file(graph_file)
        
        # Optionally save human-readable metadata
        if save_metadata:
            metadata_file = str(Path(graph_file).with_suffix('.json'))
            graph.save_metadata_json(metadata_file)
        
        return graph
    
    @staticmethod
    def load_graph(graph_file: str, silent: bool = False) -> CodeGraph:
        """Convenience method to load a graph from file."""
        return CodeGraph.load_from_file(graph_file, silent=silent)