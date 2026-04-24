package metis.core.memory

import std.unittest.testmacro.*

@Test
public class LocalMemoryIndexTest {
    @TestCase
    public func buildSqliteInsertSqlForContentBatchesAllNonEmptyLines(): Unit {
        let sql = buildSqliteInsertSqlForContent(
            "memory/demo.md",
            "first line\n\nsecond\tline\n"
        )
        @Expect(sql.contains("memory/demo.md"), true)
        @Expect(sql.contains("1: first line"), true)
        @Expect(sql.contains("3: second    line"), true)
        @Expect(sql.contains("2:"), false)
    }
}
