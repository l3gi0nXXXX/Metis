package metis.io

protected enum Direction {
    Up | Down | Left | Right
}

protected enum ClearMode {
    | AfterCursorScreen     // Clear from cursor to end of screen
    | EntireLine           // Clear the current line and move the cursor to the start
}

protected func moveCursor(offset: Int64, direction!: Direction) {
    if (offset <= 0) {
        return
    }
    match (direction) {
        case Up => PrintUtils.printString("\u{1B}[${offset}A")
        case Down => PrintUtils.printString("\u{1B}[${offset}B")
        case Left => PrintUtils.printString("\u{1B}[${offset}D")
        case Right => PrintUtils.printString("\u{1B}[${offset}C")
    }
}

protected func moveCursor(row!: ?Int64 = None, col!: ?Int64 = None) {
    if (let Some(rr) <- row) {
        PrintUtils.printString("\u{1B}[${rr}H")
    }
    if (let Some(cc) <- col) {
        PrintUtils.printString("\u{1B}[${cc}G")
    }
}

protected func clearScreen(mode!: ClearMode) {
    match (mode) {
        case AfterCursorScreen => PrintUtils.printString("\u{1B}[J")
        case EntireLine => PrintUtils.printString("\r\u{1B}[K")
    }
}

protected func hideCursor(): Unit {
    PrintUtils.printString("\u{1B}[?25l")
}

protected func showCursor(): Unit {
    PrintUtils.printString("\u{1B}[?25h")
}

protected func clearFromPreLine() {
    moveCursor(1, direction: Up)
    moveCursor(col: 0)
    clearScreen(mode: AfterCursorScreen)
}