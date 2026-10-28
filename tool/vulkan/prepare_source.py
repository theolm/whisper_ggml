#!/usr/bin/env python3
"""Apply the Vulkan-only adapter to the checksum-pinned upstream source tree.

CPU and Apple vendored sources are deliberately not rewritten. Fail on changed
anchors rather than silently building a library with different error semantics.
"""
from pathlib import Path
import sys


def prepare(root: Path) -> None:
    path = root / "src/whisper.cpp"
    source = path.read_text()
    marker = "// WHISPER_GGML_VULKAN_ADAPTER_V1"
    if marker in source:
        return

    start = source.index("struct whisper_state * whisper_init_state(")
    end = source.index("\nstruct whisper_context_params whisper_context_default_params", start)
    section = source[start:end]
    # Scope ownership covers C++ exceptions, as well as all existing null exits.
    allocation = "    whisper_state * state = new whisper_state;"
    assert section.count(allocation) == 1
    section = section.replace(allocation, allocation + "\n    std::unique_ptr<whisper_state, decltype(&whisper_free_state)> owner(state, whisper_free_state);")
    section = section.replace("whisper_free_state(state);", "/* released by owner */")
    assert section.count("return state;") == 1
    section = section.replace("return state;", "return owner.release();")
    source = source[:start] + section + source[end:]

    start = source.index("struct whisper_context * whisper_init_from_file_with_params(const char *")
    end = source.index("\nstruct whisper_context * whisper_init_from_buffer_with_params", start)
    section = source[start:end]
    anchor = "    ctx->state = whisper_init_state(ctx);"
    assert section.count(anchor) == 1
    section = section.replace(anchor, "    std::unique_ptr<whisper_context, decltype(&whisper_free)> owner(ctx, whisper_free);\n" + anchor)
    section = section.replace("        whisper_free(ctx);", "        /* released by owner */")
    section = section.replace("    return ctx;", "    return owner.release();")
    source = source[:start] + section + source[end:]
    source = '#include <memory>\n#include "ggml-vulkan.h"\n' + source
    source += '''
// WHISPER_GGML_VULKAN_ADAPTER_V1
// Inspect the context that will execute inference, not a compile-time label or
// a separate probe device. CPU-only fallback in upstream is not GPU success.
extern "C" bool whisper_ggml_uses_vulkan(const whisper_context * ctx) {
    if (!ctx || !ctx->state) return false;
    for (auto backend : ctx->state->backends) {
        if (ggml_backend_is_vk(backend)) return true;
    }
    return false;
}
'''
    path.write_text(source)


if __name__ == "__main__":
    prepare(Path(sys.argv[1]))
