"""
Two-stage retrieval system combining semantic search with graph traversal.
"""
import re
from typing import List, Dict, Set, Tuple, Optional
from collections import defaultdict

from .models import Chunk, ChunkResult, RetrievalConfig
from .vector_store import MilvusVectorStore
from .graph import CodeGraph
from .extractor import CangjieCodeElementExtractor


class QueryAnalyzer:
    """Analyze queries to extract code elements and intent."""
    
    def __init__(self):
        self.extractor = CangjieCodeElementExtractor()
        
        # Patterns for identifying code elements in queries
        self.function_mention_pattern = re.compile(r'\b(\w+)\s*\(.*?\)', re.DOTALL)
        self.type_mention_pattern = re.compile(r'\b(?:class|struct|interface|enum)\s+(\w+)', re.IGNORECASE)
        self.identifier_pattern = re.compile(r'\b([A-Z][a-zA-Z0-9_]*|[a-z][a-zA-Z0-9_]*[A-Z][a-zA-Z0-9_]*)\b')
        
        # Intent keywords
        self.intent_patterns = {
            'definition': ['what is', 'define', 'definition of', 'explain'],
            'usage': ['how to use', 'example', 'usage', 'use', 'implement'],
            'troubleshooting': ['error', 'problem', 'issue', 'debug', 'fix', 'troubleshoot'],
            'comparison': ['vs', 'versus', 'compare', 'difference', 'between']
        }
    
    def analyze_query(self, query: str) -> Dict[str, any]:
        """Analyze query to extract elements and intent."""
        query_lower = query.lower()
        
        # Extract mentioned code elements
        code_elements = set()
        
        # Look for function calls
        for match in self.function_mention_pattern.finditer(query):
            code_elements.add(match.group(1))
        
        # Look for type mentions
        for match in self.type_mention_pattern.finditer(query):
            code_elements.add(match.group(1))
        
        # Look for likely identifiers (CamelCase, etc.)
        for match in self.identifier_pattern.finditer(query):
            identifier = match.group(1)
            if len(identifier) > 2 and not identifier.lower() in {'the', 'and', 'for', 'can', 'how'}:
                code_elements.add(identifier)
        
        # Determine query intent
        intent = 'general'
        for intent_type, keywords in self.intent_patterns.items():
            if any(keyword in query_lower for keyword in keywords):
                intent = intent_type
                break
        
        return {
            'code_elements': list(code_elements),
            'intent': intent,
            'original_query': query,
            'query_terms': query_lower.split()
        }


class ResultRanker:
    """Rank and filter retrieval results."""
    
    def __init__(self, graph: CodeGraph):
        self.graph = graph
    
    def rank_results(self, chunks: List[ChunkResult], query_analysis: Dict[str, any], 
                    config: RetrievalConfig) -> List[ChunkResult]:
        """Rank chunks based on relevance and graph centrality."""
        if not chunks:
            return []
        
        # Calculate combined scores
        scored_chunks = []
        for chunk in chunks:
            combined_score = self._calculate_combined_score(chunk, query_analysis, config)
            chunk.score = combined_score
            scored_chunks.append(chunk)
        
        # Sort by score
        scored_chunks.sort(key=lambda x: x.score, reverse=True)
        
        # Apply diversity filtering if needed
        if config.max_total_chunks < len(scored_chunks):
            scored_chunks = self._apply_diversity_filter(
                scored_chunks[:config.max_total_chunks * 2],  # Consider more candidates
                config.max_total_chunks
            )
        
        return scored_chunks[:config.max_total_chunks]
    
    def _calculate_combined_score(self, chunk: ChunkResult, query_analysis: Dict[str, any], 
                                 config: RetrievalConfig) -> float:
        """Calculate combined score from semantic similarity and graph features."""
        semantic_score = chunk.score
        
        # Graph-based features
        graph_score = 0.0
        if config.rerank_by_graph and chunk.id in self.graph.chunk_metadata:
            # Centrality score
            centrality = self.graph.chunk_metadata[chunk.id].centrality_score
            graph_score += centrality * 0.3
            
            # Code element overlap score
            chunk_elements = set(chunk.metadata.code_elements)
            query_elements = set(query_analysis['code_elements'])
            
            if query_elements:
                overlap_ratio = len(chunk_elements & query_elements) / len(query_elements)
                graph_score += overlap_ratio * 0.4
            
            # Intent-based scoring
            intent_score = self._calculate_intent_score(chunk, query_analysis['intent'])
            graph_score += intent_score * 0.3
        
        # Combine scores (weight semantic search higher)
        combined_score = 0.7 * semantic_score + 0.3 * graph_score
        
        return combined_score
    
    def _calculate_intent_score(self, chunk: ChunkResult, intent: str) -> float:
        """Calculate score based on query intent."""
        content_lower = chunk.content.lower()
        
        intent_indicators = {
            'definition': ['definition', 'is a', 'represents', 'type of'],
            'usage': ['example', 'use', 'usage', 'implement', 'call'],
            'troubleshooting': ['error', 'problem', 'issue', 'solution', 'fix'],
            'comparison': ['vs', 'versus', 'compare', 'difference', 'unlike']
        }
        
        indicators = intent_indicators.get(intent, [])
        if not indicators:
            return 0.5  # Neutral score for unknown intents
        
        score = sum(1 for indicator in indicators if indicator in content_lower)
        return min(score / len(indicators), 1.0)
    
    def _apply_diversity_filter(self, chunks: List[ChunkResult], target_count: int) -> List[ChunkResult]:
        """Apply diversity filtering to avoid too many similar chunks."""
        if len(chunks) <= target_count:
            return chunks
        
        selected = [chunks[0]]  # Always include the top result
        
        for chunk in chunks[1:]:
            if len(selected) >= target_count:
                break
            
            # Check diversity with already selected chunks
            is_diverse = self._is_diverse_enough(chunk, selected)
            if is_diverse:
                selected.append(chunk)
        
        # Fill remaining slots if needed
        while len(selected) < target_count and len(selected) < len(chunks):
            for chunk in chunks:
                if chunk not in selected:
                    selected.append(chunk)
                    break
        
        return selected
    
    def _is_diverse_enough(self, candidate: ChunkResult, selected: List[ChunkResult]) -> bool:
        """Check if a candidate chunk is diverse enough from selected chunks."""
        candidate_elements = set(candidate.metadata.code_elements)
        
        for selected_chunk in selected:
            selected_elements = set(selected_chunk.metadata.code_elements)
            
            # If chunks are from the same file and have high element overlap, not diverse
            if (candidate.id in self.graph.chunk_metadata and 
                selected_chunk.id in self.graph.chunk_metadata):
                
                # Check if chunks are too similar
                if candidate_elements and selected_elements:
                    overlap_ratio = len(candidate_elements & selected_elements) / len(candidate_elements | selected_elements)
                    if overlap_ratio > 0.7:  # High overlap threshold
                        return False
        
        return True


class GraphRAGRetriever:
    """Main retrieval system combining semantic search with graph traversal."""
    
    def __init__(self, vector_store: MilvusVectorStore, graph: CodeGraph):
        self.vector_store = vector_store
        self.graph = graph
        self.query_analyzer = QueryAnalyzer()
        self.result_ranker = ResultRanker(graph)
    
    def retrieve(self, query: str, config: Optional[RetrievalConfig] = None) -> List[ChunkResult]:
        """Perform two-stage retrieval: semantic search + graph expansion."""
        if config is None:
            config = RetrievalConfig()
        
        # Analyze query
        query_analysis = self.query_analyzer.analyze_query(query)
        
        # Stage 1: Semantic search
        initial_chunks = self.vector_store.semantic_search(query, config.initial_k)
        
        if not initial_chunks:
            return []
        
        # Stage 2: Graph expansion
        expanded_chunk_ids = self._graph_expand(initial_chunks, query_analysis, config)
        
        # Retrieve full chunk data for expanded results
        all_chunks = self._get_chunks_by_ids(expanded_chunk_ids, initial_chunks)
        
        # Rank and filter results
        final_results = self.result_ranker.rank_results(all_chunks, query_analysis, config)
        
        return final_results
    
    def _graph_expand(self, seed_chunks: List[ChunkResult], query_analysis: Dict[str, any],
                     config: RetrievalConfig) -> Set[str]:
        """Expand initial results using graph traversal."""
        expanded = set(chunk.id for chunk in seed_chunks)
        
        # Strategy 1: Neighbor expansion
        for chunk in seed_chunks:
            if chunk.score >= config.relevance_threshold:
                neighbors = self.graph.get_neighbors(
                    chunk.id,
                    max_distance=config.max_graph_distance,
                    min_weight=0.3
                )
                expanded.update(neighbors)
        
        # Strategy 2: Element-based expansion
        mentioned_elements = query_analysis['code_elements']
        if mentioned_elements:
            for element in mentioned_elements:
                related_chunks = self.graph.get_related_by_element(element)
                # Add high-quality related chunks
                for chunk_id in related_chunks:
                    if chunk_id in self.graph.chunk_metadata:
                        centrality = self.graph.chunk_metadata[chunk_id].centrality_score
                        if centrality > 0.1:  # Only add reasonably central chunks
                            expanded.add(chunk_id)
        
        # Strategy 3: Subgraph expansion for complex queries
        if len(mentioned_elements) > 1:
            subgraph_chunks = self.graph.get_subgraph_for_elements(
                mentioned_elements,
                max_depth=1
            )
            expanded.update(subgraph_chunks)
        
        return expanded
    
    def _get_chunks_by_ids(self, chunk_ids: Set[str], 
                          initial_chunks: List[ChunkResult]) -> List[ChunkResult]:
        """Retrieve chunk data for a set of chunk IDs."""
        chunks = {}
        
        # Add initial chunks
        for chunk in initial_chunks:
            chunks[chunk.id] = chunk
        
        # Retrieve additional chunks
        for chunk_id in chunk_ids:
            if chunk_id not in chunks:
                chunk = self.vector_store.get_chunk_by_id(chunk_id)
                if chunk:
                    chunks[chunk_id] = chunk
        
        return list(chunks.values())
    
    @classmethod
    def from_directory(cls, docs_path: str, 
                      vector_store: Optional[MilvusVectorStore] = None,
                      **kwargs) -> 'GraphRAGRetriever':
        """Create a GraphRAGRetriever from a directory of markdown files."""
        from .chunker import DirectoryProcessor
        from .graph import GraphBuilder
        
        # Initialize components
        if vector_store is None:
            vector_config = kwargs.get('vector_config', {})
            vector_store = MilvusVectorStore(**vector_config)
        
        processor = DirectoryProcessor()
        graph_builder = GraphBuilder()
        
        # Process documents
        chunks = processor.process_directory(docs_path)
        
        if not chunks:
            raise ValueError(f"No chunks found in directory: {docs_path}")
        
        # Store in vector database
        vector_store.store_chunks(chunks)
        
        # Build graph
        graph = graph_builder.build_graph(chunks)
        
        return cls(vector_store, graph)
    
    def get_statistics(self) -> Dict[str, any]:
        """Get statistics about the retrieval system."""
        graph_stats = self.graph.get_graph_statistics()
        
        return {
            'graph_statistics': graph_stats,
            'total_chunks': len(self.vector_store.get_all_chunk_ids()),
            'total_elements': len(self.graph.element_index)
        }