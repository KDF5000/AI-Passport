#include "../main/guide_utf8.c"
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    const uint8_t text[] = "路线·讲解";
    const size_t length = sizeof(text) - 1;

    assert(guide_utf8_complete_prefix(text, length) == length);
    assert(guide_utf8_complete_prefix(text, 1) == 0);
    assert(guide_utf8_complete_prefix(text, 2) == 0);
    assert(guide_utf8_complete_prefix(text, 3) == 3);
    assert(guide_utf8_complete_prefix(text, 4) == 3);
    assert(guide_utf8_complete_prefix(text, length - 1) == length - 3);

    const uint8_t invalid[] = {0xe8, 0x41, 0x00};
    assert(guide_utf8_complete_prefix(invalid, 2) == 0);
    assert(guide_utf8_complete_prefix(NULL, 4) == 0);

    char sanitized[64];
    const uint8_t route[] = "只有河南·戏剧幻城";
    assert(guide_utf8_sanitize(sanitized, sizeof(sanitized), route,
                               sizeof(route) - 1) == sizeof(route) - 1);
    assert(strcmp(sanitized, (const char *)route) == 0);

    const uint8_t emoji[] = "路线😀✅继续";
    guide_utf8_sanitize(sanitized, sizeof(sanitized), emoji,
                        sizeof(emoji) - 1);
    assert(strcmp(sanitized, "路线?继续") == 0);

    const uint8_t partial[] = {0xe8, 0xb7};
    assert(guide_utf8_sanitize(sanitized, sizeof(sanitized), partial,
                               sizeof(partial)) == 0);
    assert(sanitized[0] == '\0');

    puts("Guide UTF-8 boundary tests: PASS");
    return 0;
}
