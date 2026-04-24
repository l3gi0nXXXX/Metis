#include <windows.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdio.h>

#define VK_BACK 0x08
#define VK_TAB 0x09
#define VK_ENTER 0x0D
#define VK_ESCAPE 0x1B
#define VK_DELETE 0x2E
#define VK_UP 0x26
#define VK_DOWN 0x28
#define VK_LEFT 0x25
#define VK_RIGHT 0x27
#define VK_HOME 0x24
#define VK_END 0x23
#define INFINITE_VALUE 0xFFFFFFFF

// Static storage for original terminal settings
static HANDLE h_console = 0;
// Flag to track whether we are in raw mode
static int flag = 0;
static DWORD origin_mode = 0;
static UINT code_page_id = 65001;

const BYTE VK_UP_UTF8[] = {0x1B, 0x5B, 0x41};           // ESC [ A
const BYTE VK_DOWN_UTF8[] = {0x1B, 0x5B, 0x42};         // ESC [ B
const BYTE VK_LEFT_UTF8[] = {0x1B, 0x5B, 0x44};         // ESC [ D
const BYTE VK_RIGHT_UTF8[] = {0x1B, 0x5B, 0x43};        // ESC [ C
const BYTE VK_ESCAPE_UTF8[] = {0x1B};                   // ESC
const BYTE VK_BACK_UTF8[] = {0x08};                     // Backspace
const BYTE VK_DELETE_UTF8[] = {0x1B, 0x5B, 0x33, 0x7E}; // ESC [ 3 ~
const BYTE VK_HOME_UTF8[] = {0x1B, 0x5B, 0x48};         // ESC [ H
const BYTE VK_END_UTF8[] = {0x1B, 0x5B, 0x46};          // ESC [ F
const BYTE VK_TAB_UTF8[] = {0x09};                      // Tab
const BYTE VK_ENTER_UTF8[] = {0x0A};                    // LF

typedef struct
{
    WORD vk_code;
    const BYTE *utf8_buf;
    size_t buf_len;
} VkToUtf8Map;

const VkToUtf8Map vk_utf8_map[] = {
    {VK_UP, VK_UP_UTF8, sizeof(VK_UP_UTF8)},
    {VK_DOWN, VK_DOWN_UTF8, sizeof(VK_DOWN_UTF8)},
    {VK_LEFT, VK_LEFT_UTF8, sizeof(VK_LEFT_UTF8)},
    {VK_RIGHT, VK_RIGHT_UTF8, sizeof(VK_RIGHT_UTF8)},
    {VK_BACK, VK_BACK_UTF8, sizeof(VK_BACK_UTF8)},
    {VK_TAB, VK_TAB_UTF8, sizeof(VK_TAB_UTF8)},
    {VK_ESCAPE, VK_ESCAPE_UTF8, sizeof(VK_ESCAPE_UTF8)},
    {VK_DELETE, VK_DELETE_UTF8, sizeof(VK_DELETE_UTF8)},
    {VK_HOME, VK_HOME_UTF8, sizeof(VK_HOME_UTF8)},
    {VK_END, VK_END_UTF8, sizeof(VK_END_UTF8)},
    {VK_ENTER, VK_ENTER_UTF8, sizeof(VK_ENTER_UTF8)},
};

static int vk_map_count = sizeof(vk_utf8_map) / sizeof(VkToUtf8Map);

BOOL isCommonVirtualKey(WORD vkCode)
{
    switch (vkCode)
    {
    case VK_BACK:
    case VK_TAB:
    case VK_ENTER:
    case VK_ESCAPE:
    case VK_DELETE:
    case VK_UP:
    case VK_DOWN:
    case VK_LEFT:
    case VK_RIGHT:
    case VK_HOME:
    case VK_END:
        return TRUE;
    default:
        return 0;
    }
}

BOOL WINAPI CtrlHandler(DWORD fdwCtrlType);

int enterRaw()
{
    SetConsoleCP(code_page_id);
    SetConsoleOutputCP(code_page_id);
    h_console = GetStdHandle(STD_INPUT_HANDLE);
    if (h_console == INVALID_HANDLE_VALUE)
    {
        return FALSE;
    }

    if (!flag)
    {
        if (!GetConsoleMode(h_console, &origin_mode))
        {
            return FALSE;
        }
        DWORD raw_mode = origin_mode;
        raw_mode &= ~ENABLE_ECHO_INPUT;
        raw_mode &= ~ENABLE_LINE_INPUT;
        raw_mode &= ~ENABLE_MOUSE_INPUT;
        raw_mode &= ~ENABLE_WINDOW_INPUT;
        if (!SetConsoleMode(h_console, raw_mode))
        {
            return FALSE;
        }
        if (!SetConsoleCtrlHandler(CtrlHandler, TRUE))
        {
            SetConsoleMode(h_console, origin_mode);
            return FALSE;
        }
        flag = 1;
    }
    return TRUE;
}

void exitRaw()
{
    if (flag)
    {
        SetConsoleMode(h_console, origin_mode);
        SetConsoleCtrlHandler(CtrlHandler, FALSE);
        flag = 0;
    }
}

BOOL WINAPI CtrlHandler(DWORD fdwCtrlType)
{
    switch (fdwCtrlType)
    {
    case CTRL_C_EVENT:
    case CTRL_BREAK_EVENT:
    case CTRL_CLOSE_EVENT:
    case CTRL_LOGOFF_EVENT:
    case CTRL_SHUTDOWN_EVENT:
        exitRaw();
        return FALSE;
    default:
        return FALSE;
    }
}

/*
 *Function: Reads console input characters, compatible with both ASCII and wide characters, and returns results via pointers.
 *Parameter Description:
 *charValuePtr: Stores the character value (uses the lower 8 bits for ASCII characters; stores the 16-bit value directly for wide characters).
 *isVirtualPtr: Indicates whether the input is a virtual key (TRUE = virtual key, FALSE = regular character).
 * return TRUE if continue FALSE if error
 */
BOOL getConsoleChar(WORD *charValuePtr, BOOL *isVirtualPtr)
{
    *charValuePtr = 0;
    *isVirtualPtr = FALSE;
    if (charValuePtr == NULL || isVirtualPtr == NULL)
    {
        return FALSE;
    }
    INPUT_RECORD inputRecord;
    DWORD eventsRead;

    if (!ReadConsoleInputW(h_console, &inputRecord, 1, &eventsRead) || eventsRead != 1)
    {
        return FALSE;
    }

    if (inputRecord.EventType == KEY_EVENT && inputRecord.Event.KeyEvent.bKeyDown)
    {
        KEY_EVENT_RECORD keyEvent = inputRecord.Event.KeyEvent;
        if (isCommonVirtualKey(keyEvent.wVirtualKeyCode))
        {
            *isVirtualPtr = TRUE;
            *charValuePtr = keyEvent.wVirtualKeyCode;
        }
        else if (keyEvent.uChar.UnicodeChar != 0)
        {
            *isVirtualPtr = FALSE;
            *charValuePtr = keyEvent.uChar.UnicodeChar;
        }
        else if (keyEvent.uChar.AsciiChar != 0)
        {
            *isVirtualPtr = FALSE;
            *charValuePtr = keyEvent.uChar.AsciiChar;
        }
        else
        {
            *isVirtualPtr = TRUE;
            *charValuePtr = 0;
        }
        return TRUE;
    }
    return TRUE;
}

BOOL is_high_surrogate(WORD wchar)
{
    return (wchar >= 0xD800 && wchar <= 0xDBFF);
}

BOOL is_low_surrogate(WORD wchar)
{
    return (wchar >= 0xDC00 && wchar <= 0xDFFF);
}

uint32_t merge_surrogate_pair(WORD high, WORD low)
{
    return 0x10000U + ((uint32_t)(high - 0xD800) << 10) + (uint32_t)(low - 0xDC00);
}

/**
 * return 0: SINGLE WORD ONLY
 *        1: LOW SURROGATE NEEDED
 *        2：DOUBLE WORD READED
 *       -1: ILLEAGEL => SKIP
 */
int get_codepoint(WORD wchar, DWORD *out_codepoint, WORD *high_surrogate)
{
    if (out_codepoint == NULL || high_surrogate == NULL)
        return -1;

    if (is_high_surrogate(wchar))
    {
        *high_surrogate = wchar;
        return 1;
    }

    if (*high_surrogate != 0 && is_low_surrogate(wchar))
    {
        WORD high = *high_surrogate;
        *high_surrogate = 0;
        *out_codepoint = merge_surrogate_pair(high, wchar);
        return 2;
    }

    // ILLEGAL
    if (is_low_surrogate(wchar))
    {
        return -1;
    }

    // SINGLE SURROGATE
    *out_codepoint = (DWORD)wchar;
    return 0;
}

int codepoint_to_utf8(DWORD codepoint, BYTE *out_buf)
{
    if (out_buf == NULL)
        return -1;

    // ILLEAGAL CHECKPOIT：USING RELACE BYTES U+FFFD（UTF-8: 0xEF 0xBF 0xBD）
    if (codepoint > 0x10FFFF || (codepoint >= 0xD800 && codepoint <= 0xDFFF))
    {
        out_buf[0] = 0xEF;
        out_buf[1] = 0xBF;
        out_buf[2] = 0xBD;
        return 3;
    }

    // U+0000 ~ U+007F & ASCII
    if (codepoint <= 0x7F)
    {
        out_buf[0] = (BYTE)codepoint;
        return 1;
    }
    // U+0080 ~ U+07FF
    else if (codepoint <= 0x7FF)
    {
        out_buf[0] = 0xC0 | (BYTE)(codepoint >> 6);   // 110xxxxx
        out_buf[1] = 0x80 | (BYTE)(codepoint & 0x3F); // 10xxxxxx
        return 2;
    }
    // U+0800 ~ U+FFFF
    else if (codepoint <= 0xFFFF)
    {
        out_buf[0] = 0xE0 | (BYTE)(codepoint >> 12);         // 1110xxxx
        out_buf[1] = 0x80 | (BYTE)((codepoint >> 6) & 0x3F); // 10xxxxxx
        out_buf[2] = 0x80 | (BYTE)(codepoint & 0x3F);        // 10xxxxxx
        return 3;
    }
    // U+10000 ~ U+10FFFF
    else
    {
        out_buf[0] = 0xF0 | (BYTE)(codepoint >> 18);          // 11110xxx
        out_buf[1] = 0x80 | (BYTE)((codepoint >> 12) & 0x3F); // 10xxxxxx
        out_buf[2] = 0x80 | (BYTE)((codepoint >> 6) & 0x3F);  // 10xxxxxx
        out_buf[3] = 0x80 | (BYTE)(codepoint & 0x3F);         // 10xxxxxx
        return 4;
    }
}

int find_vk_utf8(WORD vk_code, BYTE *out_buf)
{
    if (out_buf == NULL)
        return -1;

    for (size_t i = 0; i < vk_map_count; i++)
    {
        if (vk_utf8_map[i].vk_code == vk_code)
        {
            memcpy(out_buf, vk_utf8_map[i].utf8_buf, vk_utf8_map[i].buf_len);
            return vk_utf8_map[i].buf_len;
        }
    }
    return -1;
}

/**
 * get WCHAR (2BYTES)
 * @param out_bytes: 输出UTF-8字节的缓冲区（需提前分配至少4字节，建议8字节冗余）
 * @return: out_bytes size
 */
int rawGetBytes(BYTE *out_bytes)
{
    if (out_bytes == NULL) return -1;

    WORD high_surrogate = 0;
    while (1)
    {
        INPUT_RECORD inputRecord;
        DWORD eventsRead;

        if (!ReadConsoleInputW(h_console, &inputRecord, 1, &eventsRead) || eventsRead != 1)
        {
            return -1;
        }

        if (inputRecord.EventType != KEY_EVENT || !inputRecord.Event.KeyEvent.bKeyDown)
        {
            continue;
        }

        KEY_EVENT_RECORD keyEvent = inputRecord.Event.KeyEvent;
        BOOL ctrlPressed = (keyEvent.dwControlKeyState & LEFT_CTRL_PRESSED) ||
                           (keyEvent.dwControlKeyState & RIGHT_CTRL_PRESSED);
        WORD vkCode = keyEvent.wVirtualKeyCode;

        // Handle Ctrl+Arrow
        if (ctrlPressed && vkCode == VK_RIGHT) {
            out_bytes[0] = 0xE2; out_bytes[1] = 0x9E; out_bytes[2] = 0xA1;
            return 3;
        }
        if (ctrlPressed && vkCode == VK_LEFT) {
            out_bytes[0] = 0xE2; out_bytes[1] = 0xAC; out_bytes[2] = 0x85;
            return 3;
        }

        // Normal virtual keys
        if (isCommonVirtualKey(vkCode))
        {
            int size = find_vk_utf8(vkCode, out_bytes);
            if (size > 0) return size;
            continue;
        }

        // Normal characters
        WORD wchar = keyEvent.uChar.UnicodeChar;
        if (wchar == 0) wchar = keyEvent.uChar.AsciiChar;
        if (wchar == 0) continue;

        DWORD codepoint;
        int res = get_codepoint(wchar, &codepoint, &high_surrogate);
        if (res == 2 || res == 0)
        {
            int size = codepoint_to_utf8(codepoint, out_bytes);
            if (size > 0) return size;
        }
    }
    return -1;
}

/**
 * Reads input and returns:
 * - Normal UTF-8 characters as-is
 * - Arrow keys mapped to Unicode arrow symbols (U+2190-U+2193) in UTF-8
 *
 * @param bytes Output buffer (at least 4 bytes)
 * @return Number of bytes written, TRUE on EOF, FALSE on error
 */
int getRawUtf8(BYTE *bytes)
{
    if (bytes == NULL)
    {
        return -1;
    }
    int size = rawGetBytes(bytes);
    if (size < 0)
    {
        return -1;
    }

    BYTE c = bytes[0];

    // --- 0. Escape Sequence (Special Keys) ---
    if (c == 0x1b)
    { // ESC
        if (size == 1)
        { // Just ESC
            return 1;
        }
        c = bytes[1];
        if (c != 0x5b)
        {
            return 1; // Just ESC
        }
        c = bytes[2];
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

        case 'H': // Home → Ctrl+A (0x01)
            bytes[0] = 0x01;
            return 1;

        case 'F': // End → Ctrl+E (0x05)
            bytes[0] = 0x05;
            return 1;

        case '3':                              // Delete key: ESC [ 3 ~ → U+2326 (⌦ ERASE TO THE RIGHT)
            if (size >= 4 && bytes[3] == 0x7E) // Verify it's ESC [ 3 ~
            {
                bytes[0] = 0xE2; // UTF-8 encoding of U+2326
                bytes[1] = 0x8C;
                bytes[2] = 0xA6;
                return 3;
            }
            return 0; // Invalid sequence

        default:
            return 0; // Unknown CSI
        }
    }

    return size;
}

bool checkHasInput(uint32_t dwTimeoutMs)
{
    DWORD waitTime = (dwTimeoutMs == 0) ? INFINITE_VALUE : dwTimeoutMs;
    DWORD waitResult = WaitForSingleObject(h_console, waitTime);

    if (waitResult != WAIT_OBJECT_0)
    {
        return false;
    }

    // Peek at console input to check for valid key events
    // We need to filter out key-up events and other non-input events
    INPUT_RECORD inputRecords[128];
    DWORD eventsRead;

    if (!PeekConsoleInputW(h_console, inputRecords, 128, &eventsRead) || eventsRead == 0)
    {
        return false;
    }

    // Check if there's any valid key down event with actual input
    for (DWORD i = 0; i < eventsRead; i++)
    {
        if (inputRecords[i].EventType == KEY_EVENT && inputRecords[i].Event.KeyEvent.bKeyDown)
        {
            KEY_EVENT_RECORD keyEvent = inputRecords[i].Event.KeyEvent;
            // Check if it's an actual character or common virtual key
            if (keyEvent.uChar.UnicodeChar != 0 || isCommonVirtualKey(keyEvent.wVirtualKeyCode))
            {
                return true;
            }
        }
    }

    return false;
}

/**
 * listen ESC Button, make sure in `raw mode` before calling this function
 * @return: keyCode len:
 *   -1 = no input in  dwTimeoutMs ms
 *   1  = ASCII
 *   2  = CHECKPOINT (half, illegal)
 */
int getByte(DWORD dwTimeoutMs, WORD *keyCode)
{
    if (!checkHasInput(dwTimeoutMs))
    {
        return -1;
    }
    BOOL isVirtual = FALSE;
    if (!getConsoleChar(keyCode, &isVirtual))
    {
        return -1;
    }
    if (is_high_surrogate(*keyCode) || is_low_surrogate(*keyCode))
    {
        return 2;
    }
    return 1;
}