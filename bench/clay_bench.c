/*
 * clay_bench.c — Clay.h benchmark harness aligned with bench/ui_bench_lib.lua.
 *
 * Shared workloads:
 *   1. flat_list     — header + N stacked cards with title/detail text
 *   2. text_heavy    — header + N wrapped text cards
 *   3. nested_panels — header + N groups, each with 6 cards in two rows
 *   4. inspector_mini — legacy editor-style comparison scene
 *
 * Build:
 *   cc -O2 -DCLAY_IMPLEMENTATION -I./bench -o bench/clay_bench bench/clay_bench.c -lm
 *
 * Usage:
 *   ./bench/clay_bench [workload] [count] [iterations]
 */

#define CLAY_IMPLEMENTATION
#include "clay.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static const int VIEW_W = 1280;
static const int VIEW_H = 800;
static const char *LOREM = "Compiler-shaped UI benchmark text wrapping through the approximate text backend with enough words to trigger layout work repeatedly.";

static int had_error = 0;

static void on_error(Clay_ErrorData e) {
    had_error = 1;
    fprintf(stderr, "clay error: %.*s\n", e.errorText.length, e.errorText.chars);
}

static Clay_Dimensions measure_text(Clay_StringSlice text, Clay_TextElementConfig *cfg, void *ud) {
    (void)ud;
    float lh = cfg->lineHeight > 0 ? (float)cfg->lineHeight : (float)cfg->fontSize * 1.2f;
    return (Clay_Dimensions){ .width = (float)text.length * (float)cfg->fontSize * 0.6f, .height = lh };
}

static Clay_Color rgba(float r, float g, float b, float a) {
    return (Clay_Color){ r * 255, g * 255, b * 255, a * 255 };
}

static Clay_String cstr(const char *s) {
    return (Clay_String){ .isStaticallyAllocated = false, .length = (int32_t)strlen(s), .chars = s };
}

static Clay_TextElementConfig *tcfg_nowrap(uint16_t sz, Clay_Color c) {
    return CLAY_TEXT_CONFIG({
        .fontSize = sz,
        .lineHeight = (uint16_t)(sz * 1.2f),
        .textColor = c,
        .wrapMode = CLAY_TEXT_WRAP_NONE,
    });
}

static Clay_TextElementConfig *tcfg_wrap(uint16_t sz, Clay_Color c) {
    return CLAY_TEXT_CONFIG({
        .fontSize = sz,
        .lineHeight = (uint16_t)(sz * 1.2f),
        .textColor = c,
        .wrapMode = CLAY_TEXT_WRAP_WORDS,
    });
}

static void *dummy_image = (void*)0x1;

extern int32_t Clay__defaultMaxElementCount;
extern int32_t Clay__defaultMaxMeasureTextWordCacheCount;

static void *g_mem = NULL;
static int g_cap = 0;
static Clay_Context *g_ctx = NULL;

static void ensure_ctx(int max_elems, int vw, int vh) {
    if (g_ctx && g_cap >= max_elems) {
        Clay_SetCurrentContext(g_ctx);
        Clay_SetLayoutDimensions((Clay_Dimensions){ (float)vw, (float)vh });
        return;
    }
    if (g_mem) {
        free(g_mem);
        g_mem = NULL;
        g_ctx = NULL;
        g_cap = 0;
    }

    Clay__defaultMaxElementCount = max_elems;
    Clay__defaultMaxMeasureTextWordCacheCount = max_elems * 8;

    uint32_t arena_size = (uint32_t)max_elems * 2048;
    if (arena_size < 8 * 1024 * 1024) arena_size = 8 * 1024 * 1024;
    g_mem = malloc(arena_size);
    Clay_Arena arena = Clay_CreateArenaWithCapacityAndMemory(arena_size, g_mem);
    g_ctx = Clay_Initialize(arena, (Clay_Dimensions){ (float)vw, (float)vh }, (Clay_ErrorHandler){ on_error, NULL });
    Clay_SetMeasureTextFunction(measure_text, NULL);
    Clay_SetCullingEnabled(false);
    g_cap = max_elems;
}

static int build_flat_list(int n) {
    ensure_ctx(n * 32 + 1024, VIEW_W, VIEW_H);
    had_error = 0;
    Clay_SetPointerState((Clay_Vector2){ -1e4, -1e4 }, false);
    Clay_BeginLayout();

    CLAY(CLAY_ID("root"), {
        .layout = {
            .layoutDirection = CLAY_TOP_TO_BOTTOM,
            .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_GROW(0) },
            .padding = CLAY_PADDING_ALL(8),
            .childGap = 4,
        },
        .backgroundColor = rgba(0.06f, 0.09f, 0.16f, 1),
    }) {
        CLAY_AUTO_ID({ .layout = { .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_FIT(0) } } }) {
            CLAY_TEXT(CLAY_STRING("flat list"), tcfg_nowrap(24, rgba(1, 1, 1, 1)));
        }
        CLAY(CLAY_ID("list"), {
            .layout = {
                .layoutDirection = CLAY_TOP_TO_BOTTOM,
                .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_GROW(0) },
                .childGap = 4,
            },
        }) {
            for (int i = 0; i < n; i++) {
                char title[64], detail[96];
                snprintf(title, sizeof(title), "item %d", i + 1);
                snprintf(detail, sizeof(detail), "row detail text for benchmark item %d", i + 1);
                CLAY(CLAY_SIDI(CLAY_STRING("row"), i), {
                    .layout = {
                        .layoutDirection = CLAY_TOP_TO_BOTTOM,
                        .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_FIT(0) },
                        .padding = CLAY_PADDING_ALL(6),
                        .childGap = 4,
                    },
                    .backgroundColor = (i % 2 == 0) ? rgba(0.06f, 0.09f, 0.16f, 1) : rgba(0.07f, 0.10f, 0.18f, 1),
                    .border = { .color = rgba(0.20f, 0.27f, 0.37f, 1), .width = CLAY_BORDER_ALL(1) },
                }) {
                    CLAY_TEXT(cstr(title), tcfg_nowrap(16, rgba(1, 1, 1, 1)));
                    CLAY_TEXT(cstr(detail), tcfg_nowrap(14, rgba(0.76f, 0.82f, 0.90f, 1)));
                }
            }
        }
    }

    Clay_RenderCommandArray cmds = Clay_EndLayout();
    return cmds.length;
}

static int build_text_heavy(int n) {
    ensure_ctx(n * 14 + 1024, VIEW_W, VIEW_H);
    had_error = 0;
    Clay_SetPointerState((Clay_Vector2){ -1e4, -1e4 }, false);
    Clay_BeginLayout();

    CLAY(CLAY_ID("root"), {
        .layout = {
            .layoutDirection = CLAY_TOP_TO_BOTTOM,
            .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_GROW(0) },
            .padding = CLAY_PADDING_ALL(8),
            .childGap = 6,
        },
        .backgroundColor = rgba(0.06f, 0.09f, 0.16f, 1),
    }) {
        CLAY_TEXT(CLAY_STRING("text heavy"), tcfg_nowrap(24, rgba(1, 1, 1, 1)));
        for (int i = 0; i < n; i++) {
            char buf[256];
            snprintf(buf, sizeof(buf), "%s paragraph=%d", LOREM, i + 1);
            CLAY(CLAY_SIDI(CLAY_STRING("textrow"), i), {
                .layout = {
                    .layoutDirection = CLAY_TOP_TO_BOTTOM,
                    .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_FIT(0) },
                    .padding = CLAY_PADDING_ALL(6),
                    .childGap = 4,
                },
                .backgroundColor = rgba(0.07f, 0.10f, 0.18f, 1),
                .border = { .color = rgba(0.12f, 0.18f, 0.28f, 1), .width = CLAY_BORDER_ALL(1) },
            }) {
                CLAY_TEXT(cstr(buf), tcfg_wrap(16, rgba(0.96f, 0.98f, 1.0f, 1)));
            }
        }
    }

    Clay_RenderCommandArray cmds = Clay_EndLayout();
    return cmds.length;
}

static void card_block(const char *title, const char *detail, int index_hint) {
    CLAY(CLAY_SIDI(CLAY_STRING("card"), index_hint), {
        .layout = {
            .layoutDirection = CLAY_TOP_TO_BOTTOM,
            .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_FIT(0) },
            .padding = CLAY_PADDING_ALL(6),
            .childGap = 4,
        },
        .backgroundColor = rgba(0.07f, 0.10f, 0.18f, 1),
        .border = { .color = rgba(0.12f, 0.18f, 0.28f, 1), .width = CLAY_BORDER_ALL(1) },
    }) {
        CLAY_TEXT(cstr(title), tcfg_nowrap(16, rgba(1, 1, 1, 1)));
        CLAY_TEXT(cstr(detail), tcfg_nowrap(14, rgba(0.76f, 0.82f, 0.90f, 1)));
    }
}

static int build_nested_panels(int g) {
    ensure_ctx(g * 48 + 2048, VIEW_W, VIEW_H);
    had_error = 0;
    Clay_SetPointerState((Clay_Vector2){ -1e4, -1e4 }, false);
    Clay_BeginLayout();

    CLAY(CLAY_ID("root"), {
        .layout = {
            .layoutDirection = CLAY_TOP_TO_BOTTOM,
            .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_GROW(0) },
            .padding = CLAY_PADDING_ALL(8),
            .childGap = 8,
        },
        .backgroundColor = rgba(0.06f, 0.09f, 0.16f, 1),
    }) {
        CLAY_TEXT(CLAY_STRING("nested panels"), tcfg_nowrap(24, rgba(1, 1, 1, 1)));
        for (int gi = 0; gi < g; gi++) {
            CLAY(CLAY_SIDI(CLAY_STRING("group"), gi), {
                .layout = {
                    .layoutDirection = CLAY_TOP_TO_BOTTOM,
                    .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_FIT(0) },
                    .padding = CLAY_PADDING_ALL(6),
                    .childGap = 6,
                },
                .backgroundColor = rgba(0.04f, 0.07f, 0.12f, 1),
                .border = { .color = rgba(0.20f, 0.27f, 0.37f, 1), .width = CLAY_BORDER_ALL(1) },
            }) {
                char group_title[32];
                snprintf(group_title, sizeof(group_title), "group %d", gi + 1);
                CLAY_TEXT(cstr(group_title), tcfg_nowrap(18, rgba(0.55f, 0.78f, 1.0f, 1)));

                for (int row = 0; row < 2; row++) {
                    CLAY_AUTO_ID({
                        .layout = {
                            .layoutDirection = CLAY_LEFT_TO_RIGHT,
                            .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_FIT(0) },
                            .childGap = 6,
                        },
                    }) {
                        for (int col = 0; col < 3; col++) {
                            int idx = gi * 6 + row * 3 + col + 1;
                            char card_title[32];
                            snprintf(card_title, sizeof(card_title), "card %d", idx);
                            CLAY_AUTO_ID({
                                .layout = {
                                    .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_FIT(0) },
                                },
                            }) {
                                card_block(card_title, "nested panel payload", idx);
                            }
                        }
                    }
                }
            }
        }
    }

    Clay_RenderCommandArray cmds = Clay_EndLayout();
    return cmds.length;
}

static int build_inspector_mini(int n) {
    ensure_ctx(n * 24 + 2048, VIEW_W, VIEW_H);
    had_error = 0;
    Clay_SetPointerState((Clay_Vector2){ -1e4, -1e4 }, false);
    Clay_BeginLayout();

    CLAY(CLAY_ID("root"), {
        .layout = { .layoutDirection = CLAY_TOP_TO_BOTTOM, .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_GROW(0) }, .padding = CLAY_PADDING_ALL(10), .childGap = 10 },
        .backgroundColor = rgba(0.08f, 0.09f, 0.11f, 1),
    }) {
        CLAY(CLAY_ID("toolbar"), {
            .layout = { .layoutDirection = CLAY_LEFT_TO_RIGHT, .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_FIXED(40) }, .padding = CLAY_PADDING_ALL(6), .childGap = 6, .childAlignment = { .y = CLAY_ALIGN_Y_CENTER } },
            .backgroundColor = rgba(0.10f, 0.11f, 0.14f, 1),
        }) {
            for (int i = 0; i < 3; i++) {
                char buf[16];
                snprintf(buf, sizeof(buf), "Tab %d", i);
                CLAY_AUTO_ID({ .layout = { .padding = CLAY_PADDING_ALL(6), .sizing = { .width = CLAY_SIZING_FIT(0), .height = CLAY_SIZING_FIT(0) } }, .backgroundColor = rgba(0.18f, 0.24f, 0.36f, 1) }) {
                    CLAY_TEXT(cstr(buf), tcfg_nowrap(14, rgba(1, 1, 1, 1)));
                }
            }
        }

        CLAY(CLAY_ID("main"), { .layout = { .layoutDirection = CLAY_LEFT_TO_RIGHT, .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_GROW(0) }, .childGap = 10 } }) {
            CLAY(CLAY_ID("assets"), {
                .layout = { .layoutDirection = CLAY_TOP_TO_BOTTOM, .sizing = { .width = CLAY_SIZING_FIXED(260), .height = CLAY_SIZING_GROW(0) }, .padding = CLAY_PADDING_ALL(8), .childGap = 4 },
                .backgroundColor = rgba(0.12f, 0.13f, 0.15f, 1),
            }) {
                CLAY_TEXT(CLAY_STRING("Assets"), tcfg_nowrap(18, rgba(0.96f, 0.97f, 0.98f, 1)));
                for (int i = 0; i < n; i++) {
                    char buf[32];
                    snprintf(buf, sizeof(buf), "Asset %d", i);
                    CLAY(CLAY_SIDI(CLAY_STRING("asset"), i), {
                        .layout = { .padding = CLAY_PADDING_ALL(5), .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_FIT(0) } },
                        .backgroundColor = (i % 2 == 0) ? rgba(0.14f, 0.15f, 0.18f, 1) : rgba(0.12f, 0.13f, 0.16f, 1),
                    }) {
                        CLAY_TEXT(cstr(buf), tcfg_nowrap(14, rgba(0.92f, 0.93f, 0.95f, 1)));
                    }
                }
            }
            CLAY(CLAY_ID("center"), { .layout = { .layoutDirection = CLAY_TOP_TO_BOTTOM, .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_GROW(0) }, .childGap = 8 } }) {
                CLAY_TEXT(CLAY_STRING("Preview"), tcfg_nowrap(20, rgba(0.96f, 0.97f, 0.98f, 1)));
                CLAY(CLAY_ID("image"), { .layout = { .sizing = { .width = CLAY_SIZING_FIXED(320), .height = CLAY_SIZING_FIXED(180) } }, .image = { .imageData = &dummy_image } }) {}
            }
            CLAY(CLAY_ID("inspector"), {
                .layout = { .layoutDirection = CLAY_TOP_TO_BOTTOM, .sizing = { .width = CLAY_SIZING_FIXED(240), .height = CLAY_SIZING_GROW(0) }, .padding = CLAY_PADDING_ALL(8), .childGap = 4 },
                .backgroundColor = rgba(0.12f, 0.13f, 0.15f, 1),
            }) {
                CLAY_TEXT(CLAY_STRING("Inspector"), tcfg_nowrap(18, rgba(0.96f, 0.97f, 0.98f, 1)));
                for (int i = 0; i < 12; i++) {
                    char lhs[24], rhs[24];
                    snprintf(lhs, sizeof(lhs), "Field %d", i);
                    snprintf(rhs, sizeof(rhs), "%d", 100 + i * 7);
                    CLAY_AUTO_ID({ .layout = { .layoutDirection = CLAY_LEFT_TO_RIGHT, .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_FIT(0) }, .childGap = 6 } }) {
                        CLAY_TEXT(cstr(lhs), tcfg_nowrap(14, rgba(0.92f, 0.93f, 0.95f, 1)));
                        CLAY_AUTO_ID({ .layout = { .sizing = { .width = CLAY_SIZING_GROW(0), .height = CLAY_SIZING_FIT(0) } } }) {}
                        CLAY_TEXT(cstr(rhs), tcfg_nowrap(14, rgba(0.72f, 0.80f, 0.96f, 1)));
                    }
                }
            }
        }
    }

    Clay_RenderCommandArray cmds = Clay_EndLayout();
    return cmds.length;
}

static double now_sec(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

int main(int argc, char **argv) {
    const char *workload = argc > 1 ? argv[1] : "all";
    int count = argc > 2 ? atoi(argv[2]) : 100;
    int iters = argc > 3 ? atoi(argv[3]) : 1000;

    typedef int (*build_fn)(int);
    struct { const char *name; build_fn fn; } tests[] = {
        { "flat_list",      build_flat_list },
        { "text_heavy",     build_text_heavy },
        { "nested_panels",  build_nested_panels },
        { "inspector_mini", build_inspector_mini },
    };
    int ntests = sizeof(tests) / sizeof(tests[0]);

    printf("clay_bench  count=%d  iters=%d\n", count, iters);
    printf("%-20s %10s %12s %12s %12s\n", "workload", "cmds", "total_ms", "per_iter_us", "iters/sec");

    for (int t = 0; t < ntests; t++) {
        if (strcmp(workload, "all") != 0 && strcmp(workload, tests[t].name) != 0) continue;

        int cmds = 0;
        for (int w = 0; w < 10; w++) cmds = tests[t].fn(count);

        double t0 = now_sec();
        for (int i = 0; i < iters; i++) {
            cmds = tests[t].fn(count);
        }
        double elapsed = now_sec() - t0;
        double per_us = elapsed / iters * 1e6;

        printf("%-20s %10d %12.2f %12.2f %12.0f\n",
            tests[t].name, cmds, elapsed * 1000, per_us, (double)iters / elapsed);

        if (had_error) {
            fprintf(stderr, "  *** HAD ERRORS ***\n");
        }
    }

    return 0;
}
