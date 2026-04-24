package metis.io

import std.unittest.testmacro.*

@Test
public class PrintUtilsTest {
    @TestCase
    public func renderAssistantResponseBoxUsesBorderedTitleBox(): Unit {
        let box = PrintUtils.renderAssistantResponseBox("Hello\nWorld")
        @Expect(box.contains("Metis"), true)
        @Expect(box.contains("Hello"), true)
        @Expect(box.contains("World"), true)
        @Expect(box.contains("╭"), true)
        @Expect(box.contains("╰"), true)
        @Expect(box.contains("│"), true)
    }
}
