package com.youye.privatehealthcoach

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.FitnessCenter
import androidx.compose.material.icons.outlined.PersonOutline
import androidx.compose.material.icons.outlined.Restaurant
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.material3.windowsizeclass.WindowWidthSizeClass
import androidx.compose.material3.windowsizeclass.calculateWindowSizeClass

/**
 * Android phone/tablet entry point. This first slice is intentionally useful with no Health
 * Connect, Samsung Health, Huawei Health Kit, camera, cloud account, or network connection.
 * All sensitive integrations are opt-in adapters added after their real-device checks.
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                val sizeClass = calculateWindowSizeClass(this)
                YouyeCoachAndroidApp(
                    isExpanded = sizeClass.widthSizeClass != WindowWidthSizeClass.Compact
                )
            }
        }
    }
}

private enum class AndroidDestination(val label: String, val icon: ImageVector) {
    TODAY("今天", Icons.Outlined.Checklist),
    FOOD("吃什么", Icons.Outlined.Restaurant),
    TRAINING("练什么", Icons.Outlined.FitnessCenter),
    HEALTH("健康", Icons.Outlined.FavoriteBorder),
    PROFILE("我的", Icons.Outlined.PersonOutline)
}

@Composable
private fun YouyeCoachAndroidApp(isExpanded: Boolean) {
    var selected by remember { mutableStateOf(AndroidDestination.TODAY) }
    if (isExpanded) {
        Row(Modifier.fillMaxSize()) {
            NavigationRail(Modifier.fillMaxHeight()) {
                AndroidDestination.entries.forEach { destination ->
                    NavigationRailItem(
                        selected = selected == destination,
                        onClick = { selected = destination },
                        icon = { Icon(destination.icon, contentDescription = destination.label) },
                        label = { Text(destination.label) }
                    )
                }
            }
            AndroidScreen(selected, Modifier.fillMaxSize())
        }
    } else {
        Scaffold(
            bottomBar = {
                NavigationBar {
                    AndroidDestination.entries.forEach { destination ->
                        NavigationBarItem(
                            selected = selected == destination,
                            onClick = { selected = destination },
                            icon = { Icon(destination.icon, contentDescription = destination.label) },
                            label = { Text(destination.label) }
                        )
                    }
                }
            }
        ) { padding -> AndroidScreen(selected, Modifier.fillMaxSize().padding(padding)) }
    }
}

@Composable
private fun AndroidScreen(destination: AndroidDestination, modifier: Modifier = Modifier) {
    when (destination) {
        AndroidDestination.TODAY -> TodayDailyCard(modifier)
        AndroidDestination.FOOD -> PlaceholderDailyDestination("吃什么", "按日期查看 56 天餐卡；食材不匹配时先拍照，再由你确认食材和克数后重排当天一餐。", modifier)
        AndroidDestination.TRAINING -> PlaceholderDailyDestination("练什么", "从最低版开始；相机提示将在本机 CameraX + MediaPipe 真机验收后开放，不录像、不上传。", modifier)
        AndroidDestination.HEALTH -> AndroidHealthHome(modifier)
        AndroidDestination.PROFILE -> PlaceholderDailyDestination("我的", "资料默认仅此设备保存。导出、删除、跨设备同步和朋友分享都必须由你主动确认。", modifier)
    }
}

/** This checks only the local Health Connect provider state. It does not request permission,
 * read a sample, or send data until the person explicitly enters the later consent flow. */
@Composable
private fun AndroidHealthHome(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val state = remember(context) { HealthConnectAvailabilityChecker(context).currentState() }
    val status = when (state) {
        AndroidHealthConnectionState.AVAILABLE -> "Health Connect 可用：下一步由你主动选择要授权的健康数据。当前尚未读取或写入。"
        AndroidHealthConnectionState.PROVIDER_UPDATE_REQUIRED -> "Health Connect 需要更新：更新完成前可继续手动记录状态，App 不会补造健康数据。"
        AndroidHealthConnectionState.NOT_INSTALLED -> "此设备未安装 Health Connect：可继续手动记录状态；不会自动跳转、安装或收集数据。"
        AndroidHealthConnectionState.NOT_SUPPORTED -> "当前设备或系统不支持 Health Connect：使用手动状态；Samsung/华为的其他健康服务也不会被自动替代或读取。"
    }
    LazyColumn(
        modifier = modifier,
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Text("健康", fontSize = 28.sp, fontWeight = FontWeight.Bold)
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("本机 Health Connect 状态", fontWeight = FontWeight.SemiBold)
                    Text(status)
                }
            }
        }
        item {
            Text("手动状态仍可用", fontWeight = FontWeight.SemiBold)
            Text("睡眠、精力、压力、饥饿冲动、消化、经期、疼痛、生病、用药限制和皮肤状态都不依赖健康服务。保护性退阶不需要读取外部数据。", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        item {
            Text("数据边界", fontWeight = FontWeight.SemiBold)
            Text("将来只有你逐次确认的实际开始—结束训练才会写入一条 ExerciseSessionRecord；不会写估算热量、步数、心率、距离、路线、录像或姿态结果。", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TodayDailyCard(modifier: Modifier = Modifier) {
    LazyColumn(
        modifier = modifier,
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Text("今天，只做三件事", fontSize = 28.sp, fontWeight = FontWeight.Bold)
            Text("先完成最低版；Android 健康数据尚未授权时不影响今天照着做。", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        item { DailyActionCard("早餐", "按 7 天早餐循环卡执行", "每份含克数、前置、分钟步骤与保存规则。") }
        item { DailyActionCard("训练/恢复", "先完成当天最低版", "腰腹、体态与恢复优先；疼痛、头晕或不适立即停止。") }
        item { DailyActionCard("睡前准备", "解冻、分装、饭盒与睡眠", "默认 100% 自炊；晚餐做两份，第二份按安全冷链留作明午。") }
        item {
            Text("Android 端当前状态", fontWeight = FontWeight.SemiBold)
            Text("离线日卡已设计为手机/平板原生界面。Health Connect 已有最小权限与可用性契约，但尚未在真实设备授权/读写；Samsung Health、华为 Health Kit、相机姿态与语音均须逐项真机验证，当前不会伪造已连接或已读取。", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun DailyActionCard(title: String, action: String, note: String) {
    Card(
        modifier = Modifier.fillMaxWidth().sizeIn(minHeight = 108.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(title, fontWeight = FontWeight.Bold)
            Text(action, fontSize = 18.sp)
            Text(note, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun PlaceholderDailyDestination(title: String, note: String, modifier: Modifier) {
    Surface(modifier = modifier) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(title, fontSize = 28.sp, fontWeight = FontWeight.Bold)
            Text(note, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text("这不是网页占位：该原生 Compose 页面会逐步接入与 Apple 端一致的日卡规则。未完成或未验证的系统能力不会显示为可用。")
        }
    }
}
