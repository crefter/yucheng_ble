@file:OptIn(ExperimentalTime::class)

package com.crefter.yuchengplugin.yucheng_ble.entity

import kotlinx.serialization.Serializable
import kotlin.time.ExperimentalTime
import kotlin.time.Instant

@Serializable
data class YuchengAuthToken(
    val accessToken: String,
    val tokenType: String? = "bearer",
    val refreshToken: String? = null,
    val issuedAt: Instant? = null,
    val expiresAt: Instant? = null,
    val userId: String? = null,
)