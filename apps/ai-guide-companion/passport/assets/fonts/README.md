<p align="right">
  <a href="README.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# Guide font

`SourceHanSansCN-Regular.otf` is Adobe Source Han Sans CN Regular from the
official release repository:

<https://raw.githubusercontent.com/adobe-fonts/source-han-sans/release/SubsetOTF/CN/SourceHanSansCN-Regular.otf>

It is redistributed under the SIL Open Font License 1.1 in
[`LICENSE-Source-Han-Sans.txt`](LICENSE-Source-Han-Sans.txt). The source OTF
SHA-256 is
`e2bc8a2e7f37474b774fff8db758681ece40bb6947a90d571bce9dd60671a8e4`.

`guide_font_14.c` is the LVGL bitmap font used for dynamic AI answers. It covers
printable ASCII, Latin-1 punctuation (including the middle dot), general
punctuation, CJK punctuation, CJK Unified Ideographs, and full-width forms:
`U+0020–U+007E`, `U+00A0–U+00FF`, `U+2000–U+206F`, `U+3000–U+303F`,
`U+4E00–U+9FFF`, and `U+FF00–U+FFEF`.
It was generated with `lv_font_conv` 1.5.3:

```bash
npx --yes lv_font_conv \
  --font assets/fonts/SourceHanSansCN-Regular.otf \
  --range 0x20-0x7E,0xA0-0xFF,0x2000-0x206F,0x3000-0x303F,0x4E00-0x9FFF,0xFF00-0xFFEF \
  --size 14 --bpp 2 --format lvgl \
  --no-compress --no-prefilter --no-kerning \
  --lv-font-name guide_font_14 \
  --lv-include lvgl.h \
  --output assets/fonts/guide_font_14.c
```

The generated source SHA-256 is
`add0baea549ef92be452f6f1756e80662b2e84455be9a0d6f7e31e818e106443`.
`main/CMakeLists.txt` compiles it into the application and `guide_app.c` selects
it for the response label.
