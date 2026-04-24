package metis.core.tools.code_compression.cangjie_analyzer

import std.collection.ArrayList

public class CodeEntities <: Iterable<CodeEntity> { 
    public let entities: ArrayList<CodeEntity>

    public prop size: Int {
        get() {
            entities.size
        }
    }

    public init() {
        this.entities = ArrayList<CodeEntity>()
    }

    public init(entities: Collection<CodeEntity>) {
        this.entities = ArrayList<CodeEntity>(entities)
    }

    override public func iterator(): Iterator<CodeEntity> {
        return entities.iterator()
    }

    public func addEntity(entity: CodeEntity) {
        entities.add(entity)
    }
}