/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */
#pragma once

#include "esp_err.h"

/** @brief Enables or disables automatic shutdown of the Wi-Fi AP. */
#ifndef WIFI_AP_AUTO_OFF_ENABLE
#define WIFI_AP_AUTO_OFF_ENABLE (0)
#endif

/**
 * @brief Timeout in minutes before the Wi-Fi AP is turned off automatically.
 *
 * The timeout only applies when no client is connected and the STA interface
 * is already connected.
 */
#define WIFI_AP_AUTO_OFF_TIMEOUT_MIN (10)

/** @brief Current application software version. */
#define APP_SW_VERSION "1.0.1"

/**
 * @brief Displays the boot guide image.
 */
void display_boot_guide_image(void);

/**
 * @brief Restores factory settings and reinitializes runtime state.
 */
void app_manager_factory_reset_machine(void);

/**
 * @brief Starts the application manager.
 *
 * @return
 *      - ESP_OK on success
 *      - An ESP error code if startup fails
 */
esp_err_t app_manager_start(void);

/**
 * @brief Applies the requested mode through the mode switch workflow.
 *
 * @param mode_id Mode identifier to apply.
 *
 * @return
 *      - ESP_OK on success
 *      - An ESP error code if the mode cannot be applied
 */
esp_err_t app_manager_apply_mode(const char* mode_id);

/**
 * @brief Updates the current mode record without running the full switch flow.
 *
 * @param mode_id Mode identifier to store.
 *
 * @return
 *      - ESP_OK on success
 *      - An ESP error code if the mode cannot be stored
 */
esp_err_t app_manager_set_current_mode(const char* mode_id);

/**
 * @brief Pauses automatic Wi-Fi reconnect attempts.
 */
void app_manager_pause_wifi_reconnect(void);

/**
 * @brief Resumes automatic Wi-Fi reconnect attempts.
 */
void app_manager_resume_wifi_reconnect(void);

/**
 * @brief Disconnects the STA interface while keeping the AP enabled.
 *
 * @return
 *      - ESP_OK on success
 *      - An ESP error code if disconnect fails
 */
esp_err_t app_manager_disconnect_sta_keep_ap(void);

/**
 * @brief Marks the app manager as having recent user or system activity.
 */
void app_manager_mark_activity(void);

/**
 * @brief Updates the refresh-in-progress state.
 *
 * @param in_progress True while a refresh is running, otherwise false.
 */
void app_manager_set_refresh_in_progress(bool in_progress);
