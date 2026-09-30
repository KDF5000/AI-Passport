<p align="right">
  <strong>简体中文</strong> · <a href="README.md">English</a>
</p>

# 导游应用字库

`SourceHanSansCN-Regular.otf` 是 Adobe 官方发布仓库中的思源黑体简体中文
Regular 字重：

<https://raw.githubusercontent.com/adobe-fonts/source-han-sans/release/SubsetOTF/CN/SourceHanSansCN-Regular.otf>

该字体依据 [`LICENSE-Source-Han-Sans.txt`](LICENSE-Source-Han-Sans.txt) 中的
SIL Open Font License 1.1 再分发。源 OTF 的 SHA-256 为
`e2bc8a2e7f37474b774fff8db758681ece40bb6947a90d571bce9dd60671a8e4`。

`guide_font_14.c` 是动态 AI 回答所使用的 LVGL 位图字库，覆盖可打印
ASCII、Latin-1 标点（包括中文间隔号）、通用标点、中日韩标点、CJK
统一汉字和全角字符：`U+0020–U+007E`、`U+00A0–U+00FF`、
`U+2000–U+206F`、`U+3000–U+303F`、
`U+4E00–U+9FFF` 和 `U+FF00–U+FFEF`。它使用
`lv_font_conv` 1.5.3 生成：

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

生成源码的 SHA-256 为
`add0baea549ef92be452f6f1756e80662b2e84455be9a0d6f7e31e818e106443`。
`main/CMakeLists.txt` 将其编译进应用，`guide_app.c` 将其绑定到回答标签。
