#include <termios.h>
#include <unistd.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <errno.h>
#include <poll.h>
#include <stdlib.h>

// Static storage for original terminal settings
static struct termios orig_termios;
// Flag to track whether we are in raw mode
static int raw_mode = 0;

void exitRaw();

/**
 * Enters raw input mode.
 * - Disables ICANON (line buffering)
 * - Disables ECHO (character echoing)
 * - Sets VMIN=1, VTIME=0 (return immediately after one byte)
 * - Uses cfmakeraw() for base raw settings, then disables ECHO explicitly
 *
 * @return 0 on success, -1 on error (e.g., tcgetattr fails)
 */
int enterRaw()
{
    struct termios raw;
    static int atexit_registered = 0;

    // Get current terminal attributes
    if (tcgetattr(STDIN_FILENO, &orig_termios) == -1)
    {
        return -1;
    }

    // Register atexit handler on first call to ensure cleanup
    if (!atexit_registered)
    {
        atexit(exitRaw);
        atexit_registered = 1;
    }

    // Only modify terminal if not already in raw mode
    if (!raw_mode)
    {
        raw = orig_termios;
        // cfmakeraw(&raw);                  // Apply basic raw mode (no signals, no echo, etc.)
        raw.c_lflag &= ~(ECHO | ICANON); // cfmakeraw doesn't disable ECHO, so we do it manually
        raw.c_cc[VMIN] = 1;
        raw.c_cc[VTIME] = 0;
        if (tcsetattr(STDIN_FILENO, TCSANOW, &raw) == -1)
        {
            return -1;
        }
        raw_mode = 1;
    }

    return 0;
}

/**
 * Exits raw mode and restores the original terminal settings.
 * This function is idempotent — calling it multiple times has no side effect.
 */
void exitRaw()
{
    if (raw_mode)
    {
        tcsetattr(STDIN_FILENO, TCSANOW, &orig_termios);
        raw_mode = 0;
    }
}

/**
 * Checks if there is input available on the given file descriptor with a timeout.
 * @param timeout_ms Timeout in milliseconds (0 for infinite)
 * @return true if input is available, false if timed out or error
 */
static bool hasInputTimeout(int fd, int timeout_ms)
{
    struct pollfd pfd = {
        .fd = fd,
        .events = POLLIN, // Poll read event
        .revents = 0};
    int ret = poll(&pfd, 1, timeout_ms); // One fd and with timeout timeout_ms
    return ret > 0 && (pfd.revents & POLLIN);
}

/**
 * Reads a byte asynchronously from stdin with a timeout.
 *
 * @param byte Output buffer for the byte
 * @param timeout Timeout in milliseconds (0 for infinite)
 * @return 0 on success, 1 on timeout, -1 on error
 */
static int asyncGetRawByte(unsigned char *bytePtr, int timeout_ms)
{
    if (!hasInputTimeout(STDIN_FILENO, timeout_ms))
    {
        return 1;
    }
    if (read(STDIN_FILENO, bytePtr, 1) == 1)
    {
        return 0;
    }
    else
    {
        return -1;
    }
}

bool checkHasInput(uint32_t timeout_ms)
{
    return hasInputTimeout(STDIN_FILENO, (timeout_ms == 0) ? -1 : (int)timeout_ms);
}

int getByte(uint32_t timeout, uint16_t *keyCode)
{
    unsigned char c;
    int ret = asyncGetRawByte(&c, (timeout == 0) ? -1 : (int)timeout);
    if (ret == 0)
    {
        if (c <= 0x7F)
        {
            *keyCode = (uint16_t)c;
            return 1;
        }
        else
        {
            return 2;
        }
    }
    else if (ret == 1)
    {
        return 0;
    }
    else
    {
        return -1;
    }
}

/**
 * Parses an escape sequence to the read buffer.
 */
static int parseEscapeSequence(unsigned char *bytes)
{
    int n = 0;
    unsigned char c = 0;

    if (!hasInputTimeout(STDIN_FILENO, 10))
    { // Just ESC
        return 1;
    }
    n = read(STDIN_FILENO, &c, 1);
    if (n <= 0)
        return 1; // Error, just return the first ESC
    bytes[1] = c; // Save the byte

    // CSI: ESC [
    if (c == 0x5b)
    {
        n = read(STDIN_FILENO, &c, 1);
        if (n <= 0)
            return 1; // Error, just return the first ESC
        bytes[2] = c;

        // Check for arrow keys
        switch (c)
        {
        case 'A':            // Up Arrow → U+2191 ↑
            bytes[0] = 0xE2; // UTF-8 for U+2191
            bytes[1] = 0x86;
            bytes[2] = 0x91;
            return 3;

        case 'B': // Down Arrow → U+2193 ↓
            bytes[0] = 0xE2;
            bytes[1] = 0x86;
            bytes[2] = 0x93;
            return 3;

        case 'C': // Right Arrow → U+2192 →
            bytes[0] = 0xE2;
            bytes[1] = 0x86;
            bytes[2] = 0x92;
            return 3;

        case 'D': // Left Arrow → U+2190 ←
            bytes[0] = 0xE2;
            bytes[1] = 0x86;
            bytes[2] = 0x90;
            return 3;

        case 'H': // Home → Ctrl+A
            bytes[0] = 0x01;
            return 1;

        case 'F': // End → Ctrl+E
            bytes[0] = 0x05;
            return 1;

        case '3': // DELETE → U+2326 (⌦ ERASE TO THE RIGHT)
            n = read(STDIN_FILENO, &c, 1);
            if (n <= 0)
                return 1;
            if (c != '~')
                return 1;
            bytes[0] = 0xE2; // UTF-8 encoding of U+2326
            bytes[1] = 0x8C;
            bytes[2] = 0xA6;
            return 3;

        case '1':                          // Modified keys: ESC [ 1 ; <modifier> <key>
            n = read(STDIN_FILENO, &c, 1); // Read ';'
            if (n <= 0 || c != ';')
                return 1;
            n = read(STDIN_FILENO, &c, 1); // Read modifier (2=Shift, 3=Alt, 5=Ctrl, etc.)
            if (n <= 0)
                return 1;
            unsigned char modifier = c;
            n = read(STDIN_FILENO, &c, 1); // Read key (A/B/C/D)
            if (n <= 0)
                return 1;

            // Only handle Ctrl (5) + Left/Right for now
            if (modifier == '5')
            {
                if (c == 'C')
                { // Ctrl+Right → U+27A1
                    bytes[0] = 0xE2;
                    bytes[1] = 0x9E;
                    bytes[2] = 0xA1;
                    return 3;
                }
                else if (c == 'D')
                { // Ctrl+Left → U+2B05
                    bytes[0] = 0xE2;
                    bytes[1] = 0xAC;
                    bytes[2] = 0x85;
                    return 3;
                }
            }
            // For all other modifier combinations (Shift, Alt, Ctrl+Up/Down, etc.)
            // just return ESC to avoid crashes
            return 1;

        case '2': // Insert: ESC [ 2 ~
        case '5': // PageUp: ESC [ 5 ~
        case '6': // PageDown: ESC [ 6 ~
            n = read(STDIN_FILENO, &c, 1); // Read '~'
            if (n <= 0 || c != '~')
                return 1;
            // Currently not handled, just return ESC
            return 1;

        default:
            return 1; // Unknown CSI
        }
    }
    else
    {
        return 1; // Unknown escaped chars
    }
}

/**
 * Reads input and returns:
 * - Normal UTF-8 characters as-is
 * - Arrow keys mapped to Unicode arrow symbols (U+2190-U+2193) in UTF-8
 *
 * @param bytes Output buffer (at least 4 bytes)
 * @return Number of bytes written, 0 on EOF, -1 on error
 */
int getRawUtf8(unsigned char *bytes)
{
    unsigned char c = 0;
    int n = 0;

    // Read first byte
    n = read(STDIN_FILENO, &c, 1);
    if (n <= 0)
        return n;
    bytes[0] = c;

    // --- 0. Escape Sequence (Special Keys) ---
    if (c == 0x1b)
    { // ESC
        return parseEscapeSequence(bytes);
    }

    // --- 1. ASCII (1-byte UTF-8) ---
    if ((c & 0x80) == 0x00)
    {
        return 1;
    }

    // --- 2. 2-byte UTF-8 ---
    if ((c & 0xE0) == 0xC0)
    {
        n = read(STDIN_FILENO, &bytes[1], 1);
        if (n <= 0)
            return -1;
        if ((bytes[1] & 0xC0) != 0x80)
            return -1;
        return 2;
    }

    // --- 3. 3-byte UTF-8 ---
    if ((c & 0xF0) == 0xE0)
    {
        for (int i = 1; i <= 2; i++)
        {
            n = read(STDIN_FILENO, &bytes[i], 1);
            if (n <= 0)
                return -1;
            if ((bytes[i] & 0xC0) != 0x80)
                return -1;
        }
        return 3;
    }

    // --- 4. 4-byte UTF-8 ---
    if ((c & 0xF8) == 0xF0)
    {
        for (int i = 1; i <= 3; i++)
        {
            n = read(STDIN_FILENO, &bytes[i], 1);
            if (n <= 0)
                return -1;
            if ((bytes[i] & 0xC0) != 0x80)
                return -1;
        }
        return 4;
    }

    return -1; // Invalid start byte
}