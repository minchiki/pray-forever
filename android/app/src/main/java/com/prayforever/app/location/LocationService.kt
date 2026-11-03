package com.prayforever.app.location

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Address
import android.location.Geocoder
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import android.os.Looper
import androidx.core.content.ContextCompat
import com.prayforever.app.core.SavedLocation
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.Locale
import kotlin.coroutines.resume

/**
 * Одноразовое определение местоположения + название города. Системный LocationManager —
 * без Google Play Services, работает и на устройствах без них.
 */
object LocationService {
    sealed interface Result {
        data class Success(
            val location: SavedLocation,
        ) : Result

        data object Denied : Result

        data object Unavailable : Result
    }

    /** LocationManager.FUSED_PROVIDER появился в API 31; на старых версиях такого провайдера просто нет. */
    private const val FUSED_PROVIDER = "fused"

    /** Общее время ожидания свежих координат: дольше ждать нет смысла, есть ручной выбор места. */
    private const val TIMEOUT_MILLIS = 15_000L
    private const val FRESH_ENOUGH_MILLIS = 30 * 60_000L

    fun hasPermission(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    suspend fun current(context: Context): Result {
        if (!hasPermission(context)) return Result.Denied
        val manager = context.getSystemService(LocationManager::class.java)
        // Сеть отвечает быстрее спутников; для времени намаза её точности хватает.
        val order = listOf(LocationManager.NETWORK_PROVIDER, FUSED_PROVIDER, LocationManager.GPS_PROVIDER)
        val providers = manager.getProviders(true).filter { it in order }.sortedBy(order::indexOf)
        val recent = lastKnown(manager)?.takeIf { System.currentTimeMillis() - it.time < FRESH_ENOUGH_MILLIS }
        val location =
            recent
                ?: withTimeoutOrNull(TIMEOUT_MILLIS) { providers.firstNotNullOfOrNull { request(manager, it) } }
                ?: lastKnown(manager)
                ?: return Result.Unavailable
        return Result.Success(
            SavedLocation(location.latitude, location.longitude, cityName(context, location.latitude, location.longitude)),
        )
    }

    @SuppressLint("MissingPermission")
    private fun lastKnown(manager: LocationManager): Location? =
        manager.getProviders(true).mapNotNull { runCatching { manager.getLastKnownLocation(it) }.getOrNull() }.maxByOrNull { it.time }

    @SuppressLint("MissingPermission")
    private suspend fun request(
        manager: LocationManager,
        provider: String,
    ): Location? =
        suspendCancellableCoroutine { continuation ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val signal = CancellationSignal()
                continuation.invokeOnCancellation { signal.cancel() }
                manager.getCurrentLocation(provider, signal, Runnable::run) { continuation.resume(it) }
            } else {
                val listener =
                    object : LocationListener {
                        override fun onLocationChanged(location: Location) {
                            manager.removeUpdates(this)
                            if (continuation.isActive) continuation.resume(location)
                        }

                        @Deprecated("Deprecated in Java")
                        override fun onStatusChanged(
                            provider: String?,
                            status: Int,
                            extras: android.os.Bundle?,
                        ) = Unit

                        override fun onProviderDisabled(provider: String) {
                            manager.removeUpdates(this)
                            if (continuation.isActive) continuation.resume(null)
                        }
                    }
                continuation.invokeOnCancellation { manager.removeUpdates(listener) }
                manager.requestLocationUpdates(provider, 0L, 0f, listener, Looper.getMainLooper())
            }
        }

    /** Название города; без сети или без геокодера на устройстве — null (покажутся координаты). */
    suspend fun cityName(
        context: Context,
        latitude: Double,
        longitude: Double,
    ): String? {
        if (!Geocoder.isPresent()) return null
        return withContext(Dispatchers.IO) {
            runCatching {
                @Suppress("DEPRECATION")
                Geocoder(context, Locale.getDefault())
                    .getFromLocation(latitude, longitude, 1)
                    ?.firstOrNull()
                    ?.let { it.locality ?: it.subAdminArea ?: it.adminArea }
            }.getOrNull()
        }
    }

    /** Поиск города по названию. null — поиск недоступен (нет геокодера или сети). */
    suspend fun search(
        context: Context,
        query: String,
    ): List<Address>? {
        if (!Geocoder.isPresent()) return null
        return withContext(Dispatchers.IO) {
            runCatching {
                @Suppress("DEPRECATION")
                Geocoder(context, Locale.getDefault()).getFromLocationName(query, 10).orEmpty()
            }.getOrNull()
        }
    }
}
