package com.youye.privatehealthcoach

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.HealthConnectClient.Companion.SDK_AVAILABLE
import androidx.health.connect.client.HealthConnectClient.Companion.SDK_UNAVAILABLE
import androidx.health.connect.client.HealthConnectClient.Companion.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED
import androidx.health.connect.client.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.BodyFatRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.WeightRecord
import java.time.Duration
import java.time.Instant
import java.util.UUID

/**
 * The Android equivalent of the Apple Health boundary. This is a contract and availability
 * adapter, not an implementation that silently reads or writes at launch. The permission UI and
 * actual record adapter will be enabled only after Android-device validation.
 */
enum class AndroidHealthConnectionState {
    AVAILABLE,
    PROVIDER_UPDATE_REQUIRED,
    NOT_INSTALLED,
    NOT_SUPPORTED
}

class HealthConnectAvailabilityChecker(private val context: Context) {
    fun currentState(): AndroidHealthConnectionState = when (HealthConnectClient.getSdkStatus(context)) {
        SDK_AVAILABLE -> AndroidHealthConnectionState.AVAILABLE
        SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> AndroidHealthConnectionState.PROVIDER_UPDATE_REQUIRED
        SDK_UNAVAILABLE -> AndroidHealthConnectionState.NOT_INSTALLED
        else -> AndroidHealthConnectionState.NOT_SUPPORTED
    }
}

/** Read selection is explicit; no background/history permission is included. */
enum class AndroidHealthReadMetric {
    WEIGHT,
    BODY_FAT,
    STEPS,
    SLEEP,
    RESTING_HEART_RATE,
    ACTIVE_CALORIES,
    EXERCISE
}

data class AndroidHealthPermissionPlan(
    val readMetrics: Set<AndroidHealthReadMetric> = AndroidHealthReadMetric.entries.toSet(),
    /** The only Android health write category allowed by this product. */
    val allowsConfirmedExerciseWrite: Boolean = true
)

/**
 * Permission declaration is deliberately separate from the Android manifest and from requesting
 * consent. The app must check this set before showing a successful connection; it must request it
 * only after the person presses the explicit health-connect action in a later UI slice.
 */
object AndroidHealthPermissions {
    val minimalReadPermissions: Set<String> = setOf(
        HealthPermission.getReadPermission(WeightRecord::class),
        HealthPermission.getReadPermission(BodyFatRecord::class),
        HealthPermission.getReadPermission(StepsRecord::class),
        HealthPermission.getReadPermission(SleepSessionRecord::class),
        HealthPermission.getReadPermission(RestingHeartRateRecord::class),
        HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class),
        HealthPermission.getReadPermission(ExerciseSessionRecord::class)
    )

    /** No weight/body-fat/step/calorie/heart-rate write permission is ever requested. */
    val confirmedExerciseWritePermission: String =
        HealthPermission.getWritePermission(ExerciseSessionRecord::class)

    val requestedPermissions: Set<String> = minimalReadPermissions + confirmedExerciseWritePermission
}

class HealthConnectConsentGate(private val context: Context) {
    private val availability = HealthConnectAvailabilityChecker(context)

    /** Never call this on launch to show a false “connected” state; use it only from consent UI. */
    suspend fun hasRequestedPermissions(): Boolean {
        if (availability.currentState() != AndroidHealthConnectionState.AVAILABLE) return false
        val client = HealthConnectClient.getOrCreate(context)
        return client.permissionController.getGrantedPermissions()
            .containsAll(AndroidHealthPermissions.requestedPermissions)
    }
}

enum class AndroidConfirmedExerciseKind {
    CORE_TRAINING,
    FLEXIBILITY,
    WALKING,
    CYCLING,
    SWIMMING
}

/**
 * Created only after the person stops an actual timer and explicitly confirms its type. The
 * future Health Connect adapter must translate this into only an ExerciseSessionRecord: no
 * estimated calories, distance, steps, heart rate, route, pose output or video.
 */
data class AndroidConfirmedExercise(
    val startedAt: Instant,
    val endedAt: Instant,
    val kind: AndroidConfirmedExerciseKind,
    val syncIdentifier: UUID = UUID.randomUUID()
) {
    val duration: Duration get() = Duration.between(startedAt, endedAt).coerceAtLeast(Duration.ZERO)
    val isWriteEligible: Boolean get() = !duration.isZero && !duration.isNegative
}

/** Pure preflight: availability, consent and user confirmation all have to be true before an
 * adapter may write. Calling this function does not ask for permission or create a record. */
object AndroidConfirmedExerciseWriteGate {
    fun mayWrite(
        connectionState: AndroidHealthConnectionState,
        permissionsGranted: Boolean,
        userConfirmed: Boolean,
        exercise: AndroidConfirmedExercise
    ): Boolean = connectionState == AndroidHealthConnectionState.AVAILABLE &&
        permissionsGranted && userConfirmed && exercise.isWriteEligible
}
