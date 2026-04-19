local ffi = require("ffi")

local M = {}

ffi.cdef [[
typedef unsigned char Uint8;
typedef unsigned short Uint16;
typedef unsigned int Uint32;
typedef unsigned long long Uint64;
typedef int Sint32;
typedef unsigned long size_t;

typedef struct SDL_Window SDL_Window;
typedef struct SDL_Renderer SDL_Renderer;
typedef struct SDL_Cursor SDL_Cursor;
typedef struct SDL_Texture SDL_Texture;
typedef struct SDL_GPUTexture SDL_GPUTexture;
typedef struct TTF_Font TTF_Font;
typedef struct TTF_TextEngine TTF_TextEngine;
typedef struct TTF_TextData TTF_TextData;

typedef struct SDL_Rect {
    int x;
    int y;
    int w;
    int h;
} SDL_Rect;

typedef struct SDL_FRect {
    float x;
    float y;
    float w;
    float h;
} SDL_FRect;

typedef struct SDL_FPoint {
    float x;
    float y;
} SDL_FPoint;

typedef struct SDL_FColor {
    float r;
    float g;
    float b;
    float a;
} SDL_FColor;

typedef struct SDL_Color {
    Uint8 r;
    Uint8 g;
    Uint8 b;
    Uint8 a;
} SDL_Color;

typedef struct SDL_WindowEvent {
    Uint32 type;
    Uint32 reserved;
    Uint64 timestamp;
    Uint32 windowID;
    Sint32 data1;
    Sint32 data2;
} SDL_WindowEvent;

typedef struct SDL_KeyboardEvent {
    Uint32 type;
    Uint32 reserved;
    Uint64 timestamp;
    Uint32 windowID;
    Uint32 which;
    Sint32 scancode;
    Sint32 key;
    Uint16 mod;
    Uint16 raw;
    Uint8 down;
    Uint8 repeat;
} SDL_KeyboardEvent;

typedef struct SDL_TextEditingEvent {
    Uint32 type;
    Uint32 reserved;
    Uint64 timestamp;
    Uint32 windowID;
    const char *text;
    Sint32 start;
    Sint32 length;
} SDL_TextEditingEvent;

typedef struct SDL_TextInputEvent {
    Uint32 type;
    Uint32 reserved;
    Uint64 timestamp;
    Uint32 windowID;
    const char *text;
} SDL_TextInputEvent;

typedef struct SDL_MouseMotionEvent {
    Uint32 type;
    Uint32 reserved;
    Uint64 timestamp;
    Uint32 windowID;
    Uint32 which;
    Uint32 state;
    float x;
    float y;
    float xrel;
    float yrel;
} SDL_MouseMotionEvent;

typedef struct SDL_MouseButtonEvent {
    Uint32 type;
    Uint32 reserved;
    Uint64 timestamp;
    Uint32 windowID;
    Uint32 which;
    Uint8 button;
    Uint8 down;
    Uint8 clicks;
    Uint8 padding;
    float x;
    float y;
} SDL_MouseButtonEvent;

typedef struct SDL_MouseWheelEvent {
    Uint32 type;
    Uint32 reserved;
    Uint64 timestamp;
    Uint32 windowID;
    Uint32 which;
    float x;
    float y;
    Uint32 direction;
    float mouse_x;
    float mouse_y;
    Sint32 integer_x;
    Sint32 integer_y;
} SDL_MouseWheelEvent;

typedef union SDL_Event {
    Uint32 type;
    SDL_WindowEvent window;
    SDL_KeyboardEvent key;
    SDL_TextEditingEvent edit;
    SDL_TextInputEvent text;
    SDL_MouseMotionEvent motion;
    SDL_MouseButtonEvent button;
    SDL_MouseWheelEvent wheel;
    Uint8 padding[128];
} SDL_Event;

typedef struct TTF_Text {
    char *text;
    int num_lines;
    int refcount;
    TTF_TextData *internal;
} TTF_Text;

typedef enum TTF_Direction {
    TTF_DIRECTION_INVALID = 0,
    TTF_DIRECTION_LTR = 4,
    TTF_DIRECTION_RTL = 5,
    TTF_DIRECTION_TTB = 6,
    TTF_DIRECTION_BTT = 7
} TTF_Direction;

typedef enum TTF_HorizontalAlignment {
    TTF_HORIZONTAL_ALIGN_INVALID = -1,
    TTF_HORIZONTAL_ALIGN_LEFT,
    TTF_HORIZONTAL_ALIGN_CENTER,
    TTF_HORIZONTAL_ALIGN_RIGHT
} TTF_HorizontalAlignment;

typedef Uint32 TTF_SubStringFlags;

typedef struct TTF_SubString {
    TTF_SubStringFlags flags;
    int offset;
    int length;
    int line_index;
    int cluster_index;
    SDL_Rect rect;
} TTF_SubString;

int SDL_Init(Uint32 flags);
void SDL_Quit(void);
const char *SDL_GetError(void);
SDL_Window *SDL_CreateWindow(const char *title, int w, int h, Uint32 flags);
int SDL_CreateWindowAndRenderer(const char *title, int width, int height, Uint32 window_flags, SDL_Window **window, SDL_Renderer **renderer);
SDL_Renderer *SDL_CreateRenderer(SDL_Window *window, const char *name);
Uint32 SDL_GetWindowID(SDL_Window *window);
void SDL_DestroyWindow(SDL_Window *window);
void SDL_DestroyRenderer(SDL_Renderer *renderer);
int SDL_SetRenderVSync(SDL_Renderer *renderer, int vsync);
int SDL_GetRenderOutputSize(SDL_Renderer *renderer, int *w, int *h);
int SDL_SetRenderDrawColor(SDL_Renderer *renderer, Uint8 r, Uint8 g, Uint8 b, Uint8 a);
int SDL_RenderClear(SDL_Renderer *renderer);
int SDL_RenderFillRect(SDL_Renderer *renderer, const SDL_FRect *rect);
int SDL_RenderRect(SDL_Renderer *renderer, const SDL_FRect *rect);
int SDL_RenderLine(SDL_Renderer *renderer, float x1, float y1, float x2, float y2);
int SDL_RenderLines(SDL_Renderer *renderer, const SDL_FPoint *points, int count);
int SDL_RenderPoints(SDL_Renderer *renderer, const SDL_FPoint *points, int count);
int SDL_SetRenderClipRect(SDL_Renderer *renderer, const SDL_Rect *rect);
int SDL_RenderPresent(SDL_Renderer *renderer);
int SDL_PollEvent(SDL_Event *event);
Uint64 SDL_GetTicks(void);
void SDL_Delay(Uint32 ms);
Uint16 SDL_GetModState(void);
int SDL_StartTextInput(SDL_Window *window);
int SDL_StopTextInput(SDL_Window *window);
int SDL_SetTextInputArea(SDL_Window *window, const SDL_Rect *rect, int cursor);
int SDL_SetClipboardText(const char *text);
char *SDL_GetClipboardText(void);
int SDL_HasClipboardText(void);
void SDL_free(void *mem);
SDL_Cursor *SDL_CreateSystemCursor(int id);
void SDL_DestroyCursor(SDL_Cursor *cursor);
int SDL_SetCursor(SDL_Cursor *cursor);
int SDL_ShowCursor(void);
int SDL_HideCursor(void);

int TTF_Init(void);
void TTF_Quit(void);
TTF_Font *TTF_OpenFont(const char *file, float ptsize);
void TTF_CloseFont(TTF_Font *font);
int TTF_GetFontAscent(const TTF_Font *font);
int TTF_GetFontDescent(const TTF_Font *font);
int TTF_GetFontHeight(const TTF_Font *font);
int TTF_GetFontLineSkip(const TTF_Font *font);
int TTF_GetStringSize(TTF_Font *font, const char *text, size_t length, int *w, int *h);
void TTF_SetFontWrapAlignment(TTF_Font *font, TTF_HorizontalAlignment align);
int TTF_SetFontDirection(TTF_Font *font, TTF_Direction direction);
int TTF_SetFontScript(TTF_Font *font, Uint32 script);
int TTF_SetFontLanguage(TTF_Font *font, const char *language_bcp47);
int TTF_AddFallbackFont(TTF_Font *font, TTF_Font *fallback);
Uint32 TTF_StringToTag(const char *string);
TTF_Text *TTF_CreateText(TTF_TextEngine *engine, TTF_Font *font, const char *text, size_t length);
void TTF_DestroyText(TTF_Text *text);
int TTF_SetTextDirection(TTF_Text *text, TTF_Direction direction);
int TTF_SetTextScript(TTF_Text *text, Uint32 script);
int TTF_SetTextWrapWidth(TTF_Text *text, int wrap_width);
int TTF_SetTextWrapWhitespaceVisible(TTF_Text *text, int visible);
int TTF_UpdateText(TTF_Text *text);
int TTF_GetTextSize(TTF_Text *text, int *w, int *h);
int TTF_GetTextSubString(TTF_Text *text, int offset, TTF_SubString *substring);
int TTF_GetTextSubStringForLine(TTF_Text *text, int line, TTF_SubString *substring);
TTF_SubString **TTF_GetTextSubStringsForRange(TTF_Text *text, int offset, int length, int *count);
int TTF_GetNextTextSubString(TTF_Text *text, const TTF_SubString *substring, TTF_SubString *next);
int TTF_GetTextSubStringForPoint(TTF_Text *text, int x, int y, TTF_SubString *substring);
TTF_TextEngine *TTF_CreateRendererTextEngine(SDL_Renderer *renderer);
void TTF_DestroyRendererTextEngine(TTF_TextEngine *engine);
int TTF_SetTextColor(TTF_Text *text, Uint8 r, Uint8 g, Uint8 b, Uint8 a);
int TTF_DrawRendererText(TTF_Text *text, float x, float y);
]]

local sdl = ffi.load("SDL3")
local ttf = ffi.load("SDL3_ttf")

local sdl_refcount = 0
local ttf_refcount = 0

local function error_string(prefix)
    local msg = sdl.SDL_GetError()
    if msg == nil then
        if prefix ~= nil then error(prefix, 3) end
        return "SDL error"
    end
    local text = ffi.string(msg)
    if prefix ~= nil then
        return prefix .. ": " .. text
    end
    return text
end

function M.err(prefix)
    error(error_string(prefix), 2)
end

function M.ensure_sdl(flags)
    flags = flags or 0x00000020
    if sdl_refcount == 0 then
        if sdl.SDL_Init(flags) == 0 then
            M.err("ui._sdl3: SDL_Init failed")
        end
    end
    sdl_refcount = sdl_refcount + 1
end

function M.release_sdl()
    if sdl_refcount <= 0 then return end
    sdl_refcount = sdl_refcount - 1
    if sdl_refcount == 0 then
        sdl.SDL_Quit()
    end
end

function M.ensure_ttf()
    if ttf_refcount == 0 then
        if ttf.TTF_Init() == 0 then
            M.err("ui._sdl3: TTF_Init failed")
        end
    end
    ttf_refcount = ttf_refcount + 1
end

function M.release_ttf()
    if ttf_refcount <= 0 then return end
    ttf_refcount = ttf_refcount - 1
    if ttf_refcount == 0 then
        ttf.TTF_Quit()
    end
end

M.ffi = ffi
M.sdl = sdl
M.ttf = ttf
M.C = ffi.C

M.SDL_INIT_VIDEO = 0x00000020
M.SDL_EVENT_QUIT = 0x100
M.SDL_EVENT_WINDOW_CLOSE_REQUESTED = 0x210
M.SDL_EVENT_WINDOW_RESIZED = 0x205
M.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED = 0x206
M.SDL_EVENT_WINDOW_FOCUS_GAINED = 0x20C
M.SDL_EVENT_WINDOW_FOCUS_LOST = 0x20D
M.SDL_EVENT_KEY_DOWN = 0x300
M.SDL_EVENT_KEY_UP = 0x301
M.SDL_EVENT_TEXT_EDITING = 0x302
M.SDL_EVENT_TEXT_INPUT = 0x303
M.SDL_EVENT_MOUSE_MOTION = 0x400
M.SDL_EVENT_MOUSE_BUTTON_DOWN = 0x401
M.SDL_EVENT_MOUSE_BUTTON_UP = 0x402
M.SDL_EVENT_MOUSE_WHEEL = 0x403

M.SDL_WINDOW_RESIZABLE = 0x20

M.SDL_BUTTON_LEFT = 1

M.SDLK_RETURN = 0x0000000d
M.SDLK_ESCAPE = 0x0000001b
M.SDLK_BACKSPACE = 0x00000008
M.SDLK_DELETE = 0x0000007f
M.SDLK_A = 0x00000061
M.SDLK_C = 0x00000063
M.SDLK_V = 0x00000076
M.SDLK_X = 0x00000078
M.SDLK_HOME = 0x4000004a
M.SDLK_END = 0x4000004d
M.SDLK_RIGHT = 0x4000004f
M.SDLK_LEFT = 0x40000050
M.SDLK_DOWN = 0x40000051
M.SDLK_UP = 0x40000052

M.SDL_KMOD_SHIFT = 0x0003
M.SDL_KMOD_CTRL = 0x00c0

M.SDL_SYSTEM_CURSOR_DEFAULT = 0
M.SDL_SYSTEM_CURSOR_TEXT = 1
M.SDL_SYSTEM_CURSOR_WAIT = 2
M.SDL_SYSTEM_CURSOR_CROSSHAIR = 3
M.SDL_SYSTEM_CURSOR_PROGRESS = 4
M.SDL_SYSTEM_CURSOR_NWSE_RESIZE = 5
M.SDL_SYSTEM_CURSOR_NESW_RESIZE = 6
M.SDL_SYSTEM_CURSOR_EW_RESIZE = 7
M.SDL_SYSTEM_CURSOR_NS_RESIZE = 8
M.SDL_SYSTEM_CURSOR_MOVE = 9
M.SDL_SYSTEM_CURSOR_NOT_ALLOWED = 10
M.SDL_SYSTEM_CURSOR_POINTER = 11

return M
