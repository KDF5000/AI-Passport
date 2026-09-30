idf_component_register(
    SRCS "main.c"
         "guide_app.c"
         "guide_ble.c"
         "guide_adpcm.c"
         "guide_utf8.c"
    INCLUDE_DIRS "."
    REQUIRES bsp bt nvs_flash
)

target_sources(${COMPONENT_LIB} PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../assets/fonts/guide_font_14.c"
)

# Keep large persistent records off the small ESP-IDF task stacks.
target_compile_options(${COMPONENT_LIB} PRIVATE -Werror=frame-larger-than=2048)
