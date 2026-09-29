idf_component_register(
    SRCS "main.c"
         "habit_app.c"
         "habit_model.c"
         "habit_photo_format.c"
         "habit_photo_portal.c"
         "habit_photo_store.c"
         "habit_store.c"
         "habit_store_record.c"
    INCLUDE_DIRS "."
    REQUIRES bsp esp_event esp_http_server esp_netif esp_wifi lwip nvs_flash
)

# Keep large persistent records off the small ESP-IDF task stacks.
target_compile_options(${COMPONENT_LIB} PRIVATE -Werror=frame-larger-than=2048)
