idf_component_register(
    SRCS "main.c"
         "guide_app.c"
         "guide_ble.c"
         "guide_adpcm.c"
    INCLUDE_DIRS "."
    REQUIRES bsp bt nvs_flash
)

# Keep large persistent records off the small ESP-IDF task stacks.
target_compile_options(${COMPONENT_LIB} PRIVATE -Werror=frame-larger-than=2048)
