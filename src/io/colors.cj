package metis.io

public struct AnsiColor <: ToString {
    public AnsiColor(
        private let colorContent: String) {
    }

    public static func color256(colorIndex: Int64): AnsiColor {
        return AnsiColor("\u{1b}[38;5;${colorIndex}m")
    }

    public static func colorBg256(colorIndex: Int64): AnsiColor {
        return AnsiColor("\u{1b}[48;5;${colorIndex}m")
    }

    public static func color16(colorCode: Int64): AnsiColor {
        return AnsiColor("\u{1b}[${colorCode}m")
    }

    override public func toString(): String {
        return this.colorContent
    }

    // ANSI color code definitions as static variables
    public static let RESET = AnsiColor.color16(0)
    public static let BOLD = AnsiColor.color16(1)
    public static let DIM = AnsiColor.color16(2)
    public static let ITALIC = AnsiColor.color16(3)
    public static let UNDERLINE = AnsiColor.color16(4)
    public static let STRIKE_THROUGH = AnsiColor.color16(9)

    // Foreground colors
    public static let BLACK = AnsiColor.color16(30)
    public static let RED = AnsiColor.color16(31)
    public static let GREEN = AnsiColor.color16(32)
    public static let YELLOW = AnsiColor.color16(33)
    public static let BLUE = AnsiColor.color16(34)
    public static let MAGENTA = AnsiColor.color16(35)
    public static let CYAN = AnsiColor.color16(36)
    public static let WHITE = AnsiColor.color16(37)

    // Bright foreground colors
    public static let BRIGHT_BLACK = AnsiColor.color16(90)
    public static let BRIGHT_RED = AnsiColor.color16(91)
    public static let BRIGHT_GREEN = AnsiColor.color16(92)
    public static let BRIGHT_YELLOW = AnsiColor.color16(93)
    public static let BRIGHT_BLUE = AnsiColor.color16(94)
    public static let PURPLE = AnsiColor.color16(95)
    public static let BRIGHT_CYAN = AnsiColor.color16(96)
    public static let BRIGHT_WHITE = AnsiColor.color16(97)

    // Background colors
    public static let BG_BLACK = AnsiColor.color16(40)
    public static let BG_RED = AnsiColor.color16(41)
    public static let BG_GREEN = AnsiColor.color16(42)
    public static let BG_YELLOW = AnsiColor.color16(43)
    public static let BG_BLUE = AnsiColor.color16(44)
    public static let BG_MAGENTA = AnsiColor.color16(45)
    public static let BG_CYAN = AnsiColor.color16(46)
    public static let BG_WHITE = AnsiColor.color16(47)

    public static let BG_LIGHT_GREEN = AnsiColor.colorBg256(22)   // Dark green background
    public static let BG_LIGHT_RED = AnsiColor.colorBg256(52)     // Dark red background

    // Magic CLI logo colors
    public static let LIGHT_PURPLE = AnsiColor.color256(141)
    public static let DARK_PURPLE = AnsiColor.color256(53)
    public static let VIOLET = AnsiColor.color256(99)
    public static let LAVENDER = AnsiColor.color256(183)
    public static let PLUM = AnsiColor.color256(96)
    public static let INDIGO = AnsiColor.color256(54)
    public static let ORCHID = AnsiColor.color256(170)
    public static let LOGO_MAGENTA = AnsiColor.color256(201)
    public static let PINK_PURPLE = AnsiColor.color256(213)
    public static let ROYAL_PURPLE = AnsiColor.color256(57)
    public static let AMETHYST = AnsiColor.color256(135)
    public static let PERIWINKLE = AnsiColor.color256(147)
    public static let LILAC = AnsiColor.color256(182)
    public static let MAUVE = AnsiColor.color256(139)
}

// Theme configuration struct for different color schemes
public struct ThemeConfig {
    ThemeConfig(
    public let name!: String,
    public let primary!: AnsiColor,
    public let secondary!: AnsiColor,
    public let success!: AnsiColor,
    public let warning!: AnsiColor,
    public let error!: AnsiColor,
    public let info!: AnsiColor,
    public let muted!: AnsiColor,
    public let accent!: AnsiColor,
    public let highlight!: AnsiColor,
    public let subtle!: AnsiColor,
    public let bgInput!: AnsiColor,
    public let bgSuccess!: AnsiColor,
    public let bgError!: AnsiColor
    ) {}
}

// Theme provider class for managing active theme
public class Theme {
    // Pre-defined themes
    public static let DEFAULT = ThemeConfig(
        name: "default",
        primary: AnsiColor.color256(140),
        secondary: AnsiColor.BRIGHT_BLUE,
        success: AnsiColor.color256(22),
        warning: AnsiColor.BRIGHT_YELLOW,
        error: AnsiColor.BRIGHT_RED,
        info: AnsiColor.BRIGHT_WHITE,
        muted: AnsiColor.BRIGHT_BLACK,
        accent: AnsiColor.color256(39),    // Deep sky blue
        highlight: AnsiColor.color256(226),  // Bright yellow
        subtle: AnsiColor.color256(245),    // Medium gray
        bgInput: AnsiColor.colorBg256(238),
        bgSuccess: AnsiColor.BG_LIGHT_GREEN,
        bgError: AnsiColor.BG_LIGHT_RED
    )

    public static let LIGHT = ThemeConfig(
        name: "light",
        primary: AnsiColor.color256(33),   // Deep sky blue
        secondary: AnsiColor.color256(39),  // Dodger blue
        success: AnsiColor.color256(28),    // Green
        warning: AnsiColor.color256(208),   // Orange
        error: AnsiColor.color256(196),     // Red
        info: AnsiColor.color256(240),      // Gray
        muted: AnsiColor.color256(251),     // Light gray
        accent: AnsiColor.color256(201),    // Hot pink
        highlight: AnsiColor.color256(220), // Gold
        subtle: AnsiColor.color256(188),    // Light steel blue
        bgInput: AnsiColor.colorBg256(153),
        bgSuccess: AnsiColor.colorBg256(194), // Light green
        bgError: AnsiColor.colorBg256(224)    // Light red
    )

    public static let DARK = ThemeConfig(
        name: "dark",
        primary: AnsiColor.color256(81),    // Cyan
        secondary: AnsiColor.color256(147), // Light sky blue
        success: AnsiColor.color256(84),   // Light green
        warning: AnsiColor.color256(226),  // Yellow
        error: AnsiColor.color256(203),    // Hot pink
        info: AnsiColor.color256(252),      // White
        muted: AnsiColor.color256(245),     // Gray
        accent: AnsiColor.color256(207),    // Magenta
        highlight: AnsiColor.color256(51), // Cyan
        subtle: AnsiColor.color256(238),    // Dark gray
        bgInput: AnsiColor.colorBg256(236),
        bgSuccess: AnsiColor.colorBg256(22),  // Dark green
        bgError: AnsiColor.colorBg256(52)     // Dark red
    )

    protected static var current: ThemeConfig = DEFAULT

    public static func set(theme: ThemeConfig): Unit {
        current = theme
    }

    public static func listThemes(): Array<ThemeConfig> {
        return [DEFAULT, LIGHT, DARK]
    }

    // Backward compatibility accessors
    public static prop PRIMARY: AnsiColor { get() { current.primary } }
    public static prop SECONDARY: AnsiColor { get() { current.secondary } }
    public static prop SUCCESS: AnsiColor { get() { current.success } }
    public static prop WARNING: AnsiColor { get() { current.warning } }
    public static prop ERROR: AnsiColor { get() { current.error } }
    public static prop INFO: AnsiColor { get() { current.info } }
    public static prop MUTED: AnsiColor { get() { current.muted } }
    public static prop ACCENT: AnsiColor { get() { current.accent } }
    public static prop HIGHLIGHT: AnsiColor { get() { current.highlight } }
    public static prop SUBTLE: AnsiColor { get() { current.subtle } }
    public static prop BG_INPUT: AnsiColor { get() { current.bgInput } }
    public static prop BG_SUCCESS: AnsiColor { get() { current.bgSuccess } }
    public static prop BG_ERROR: AnsiColor { get() { current.bgError } }
}

protected interface WithColor {
    func withColor(color: AnsiColor): String

    func withBgColor(bgColor: AnsiColor): String
}

extend String <: WithColor {
    public func withColor(color: AnsiColor): String {
        if (this.isEmpty()) {
            return this
        }
        return "${color}${this}${AnsiColor.RESET}"
    }

    public func withBgColor(bgColor: AnsiColor): String {
        if (this.isEmpty()) {
            return this
        }
        return "${bgColor}${this}${AnsiColor.RESET}"
    }
}
