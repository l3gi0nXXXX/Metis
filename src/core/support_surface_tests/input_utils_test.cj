package metis.core.support_surface_tests

import metis.io.*

import std.unittest.testmacro.*

@Test
public class InputUtilsTest {
    @TestCase
    public func defaultPromptIsAsciiChevronWithoutEmoji(): Unit {
        let prompt = InputUtils.buildPrompt("")
        let plain = removeAnsiEscape(prompt)

        @Expect(plain, " > ")
        @Expect(prompt.contains("🔮"), false)
    }

    @TestCase
    public func labeledPromptKeepsLabelAndChevron(): Unit {
        let prompt = InputUtils.buildPrompt("metis")
        let plain = removeAnsiEscape(prompt)

        @Expect(plain, " metis > ")
        @Expect(prompt.contains("🔮"), false)
    }
}
