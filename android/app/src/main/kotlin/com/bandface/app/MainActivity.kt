package com.bandface.app

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.ListAlt
import androidx.compose.material.icons.filled.Watch
import androidx.compose.material3.Icon
import androidx.compose.material3.Button
import androidx.compose.material3.LocalMinimumInteractiveComponentSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.unit.Dp
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val LightScheme = lightColorScheme(
    primary = Color(0xFF2D5DA8), onPrimary = Color.White,
    secondaryContainer = Color(0xFFD9E2FF), onSecondaryContainer = Color(0xFF001A41),
    background = Color(0xFFFEFBFF), onBackground = Color(0xFF1B1B1F),
    surface = Color(0xFFFEFBFF), onSurface = Color(0xFF1B1B1F),
    surfaceVariant = Color(0xFFF1F1F7), onSurfaceVariant = Color(0xFF44474F),
    outline = Color(0xFF74777F), error = Color(0xFFBA1A1A),
)
private val DarkScheme = darkColorScheme(
    primary = Color(0xFFAEC6FF), onPrimary = Color(0xFF002E69),
    secondaryContainer = Color(0xFF2F4578), onSecondaryContainer = Color(0xFFD9E2FF),
    background = Color(0xFF121316), onBackground = Color(0xFFE3E2E6),
    surface = Color(0xFF121316), onSurface = Color(0xFFE3E2E6),
    surfaceVariant = Color(0xFF1E1F24), onSurfaceVariant = Color(0xFFC4C6D0),
    outline = Color(0xFF8E9099), error = Color(0xFFFFB4AB),
)
private val Green = Color(0xFF1B7A3E)

/** Єдині відступи для всіх екранів. */
private object Dim {
    val screenH = 20.dp      // поля екрана зліва й справа
    val titleTop = 24.dp     // над заголовком екрана
    val titleBottom = 16.dp  // між заголовком і першою карткою
    val cardGap = 14.dp      // між картками
    val cardPad = 20.dp      // всередині картки
    val innerGap = 10.dp     // між елементами всередині картки
    val bottom = 16.dp       // під останньою карткою
}

class MainActivity : ComponentActivity() {
    private val vm: MainViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { App(vm) }
    }
}

@Composable
fun App(vm: MainViewModel) {
    val scheme: ColorScheme = if (isSystemInDarkTheme()) DarkScheme else LightScheme
    MaterialTheme(colorScheme = scheme) {
        var tab by remember { mutableIntStateOf(0) }
        Scaffold(
            containerColor = MaterialTheme.colorScheme.background,
            bottomBar = {
                NavigationBar(containerColor = MaterialTheme.colorScheme.surfaceVariant) {
                    val labels = listOf(R.string.tab_faces, R.string.tab_key, R.string.tab_log)
                    labels.forEachIndexed { i, l ->
                        NavigationBarItem(
                            selected = tab == i, onClick = { tab = i },
                            icon = { Icon(listOf(Icons.Filled.Watch, Icons.Filled.Key, Icons.Filled.ListAlt)[i], null) },
                            label = { Text(stringResource(l), fontWeight = if (tab == i) FontWeight.Bold else FontWeight.Normal) },
                            alwaysShowLabel = true,
                            colors = NavigationBarItemDefaults.colors(indicatorColor = MaterialTheme.colorScheme.secondaryContainer),
                        )
                    }
                }
            },
        ) { pad ->
            Column(Modifier.padding(pad).fillMaxSize().statusBarsPadding().padding(horizontal = Dim.screenH)) {
                Text(
                    stringResource(listOf(R.string.tab_faces, R.string.tab_key, R.string.tab_log)[tab]),
                    fontSize = 34.sp, modifier = Modifier.padding(top = Dim.titleTop, bottom = Dim.titleBottom),
                )
                when (tab) {
                    0 -> FacesTab(vm)
                    1 -> KeyTab(vm)
                    else -> LogTab(vm)
                }
            }
        }
    }
}

@Composable
private fun SectionCard(title: String, content: @Composable () -> Unit) {
    Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(24.dp), color = MaterialTheme.colorScheme.surfaceVariant) {
        Column(Modifier.padding(Dim.cardPad), verticalArrangement = Arrangement.spacedBy(Dim.innerGap)) {
            if (title.isNotEmpty()) Text(title, fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            content()
        }
    }
}

@Composable
private fun Tonal(text: String, enabled: Boolean = true, color: Color? = null, modifier: Modifier = Modifier, onClick: () -> Unit) {
    FilledTonalButton(
        onClick, modifier, enabled = enabled, contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
        colors = ButtonDefaults.filledTonalButtonColors(
            containerColor = MaterialTheme.colorScheme.secondaryContainer,
            contentColor = color ?: MaterialTheme.colorScheme.onSecondaryContainer,
        ),
    ) { Text(text, fontWeight = FontWeight.Medium, fontSize = 13.sp, maxLines = 1) }
}

@Composable
private fun Primary(text: String, enabled: Boolean = true, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Button(onClick, modifier.height(48.dp), enabled = enabled, contentPadding = PaddingValues(horizontal = 12.dp)) { Text(text, fontWeight = FontWeight.Medium, fontSize = 13.sp, maxLines = 1) }
}

@Composable
fun FacesTab(vm: MainViewModel) {
    val permissions = if (Build.VERSION.SDK_INT >= 31)
        arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
    else arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
    val permLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        if (it.values.all { granted -> granted }) vm.scan()
    }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) vm.pickFace(uri)
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(Dim.cardGap)) {
        SectionCard(stringResource(R.string.band_card)) {
            val name = vm.connectedName
            if (name != null) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(name, fontSize = 17.sp, maxLines = 1)
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(Modifier.size(9.dp).clip(CircleShape).background(Green))
                            Text("  " + stringResource(R.string.connected, "").trimEnd(' ', ':').trim(), color = Green, fontSize = 14.sp)
                        }
                    }
                    Tonal(stringResource(R.string.disconnect), enabled = !vm.busy) { vm.disconnect() }
                }
            } else {
                Text(stringResource(R.string.not_connected), fontSize = 18.sp)
                Tonal(stringResource(R.string.scan), enabled = !vm.busy) { permLauncher.launch(permissions) }
                for (d in vm.devices) {
                    Surface(
                        onClick = { vm.connect(d) }, modifier = Modifier.fillMaxWidth(), enabled = !vm.busy,
                        shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.background,
                    ) {
                        Column(Modifier.padding(14.dp)) {
                            Text(d.name, fontSize = 16.sp)
                            Text(d.address, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        }

        SectionCard(stringResource(R.string.install_card)) {
            Row(horizontalArrangement = Arrangement.spacedBy(18.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier.width(96.dp).height(236.dp).clip(RoundedCornerShape(48.dp))
                        .background(Color(0xFF1F1F1F)).border(BorderStroke(3.dp, Color(0xFF7A7A7A)), RoundedCornerShape(48.dp)),
                    contentAlignment = Alignment.Center,
                ) {
                    val bmp = vm.preview
                    if (bmp != null) Image(bmp.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Column(Modifier.fillMaxWidth().height(62.dp).padding(horizontal = 14.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        Text(vm.faceName ?: stringResource(R.string.no_face), fontSize = 19.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                        Text(if (vm.face != null) vm.faceInfo else stringResource(R.string.format_hint), fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                        Text(if (vm.face != null) (vm.fileName ?: " ") else stringResource(R.string.pick_hint), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                    }
                    Tonal(stringResource(if (vm.face == null) R.string.pick_face else R.string.pick_other), enabled = !vm.busy, modifier = Modifier.fillMaxWidth()) {
                        picker.launch(arrayOf("*/*"))
                    }
                    Primary(stringResource(R.string.install_band), enabled = !vm.busy && vm.face != null, modifier = Modifier.fillMaxWidth()) { vm.install() }
                    Box(Modifier.fillMaxWidth().height(30.dp).padding(horizontal = 14.dp), contentAlignment = Alignment.TopStart) {
                        val p = vm.progress
                        if (p != null) {
                            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                LinearProgressIndicator(progress = { p }, modifier = Modifier.fillMaxWidth().height(10.dp), strokeCap = androidx.compose.ui.graphics.StrokeCap.Round)
                                Row {
                                    Text(vm.progressText, Modifier.weight(1f), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                                    Text("${(p * 100).toInt()}%", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        } else vm.status?.let { Text(it, fontSize = 12.sp, color = Green, maxLines = 2) }
                    }
                }
            }
        }
        Spacer(Modifier.height(Dim.bottom - Dim.cardGap))
    }
}

@Composable
fun KeyTab(vm: MainViewModel) {
    var text by remember { mutableStateOf(vm.keyText) }
    val folder = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) vm.scanFolder(uri)
    }
    val file = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) vm.importKey(uri)
    }
    if (text != vm.keyText && vm.keyText.isNotEmpty()) text = vm.keyText

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(Dim.cardGap)) {
        SectionCard(stringResource(R.string.key_title)) {
            OutlinedTextField(
                text, { text = it; vm.saveKey(it) }, Modifier.fillMaxWidth(),
                placeholder = { Text(stringResource(R.string.key_hint)) }, singleLine = true,
                textStyle = androidx.compose.ui.text.TextStyle(fontFamily = FontFamily.Monospace, fontSize = 15.sp),
                shape = RoundedCornerShape(8.dp),
            )
            Primary(stringResource(R.string.find_auto), modifier = Modifier.fillMaxWidth().height(52.dp)) { folder.launch(null) }
            Tonal(stringResource(R.string.paste), modifier = Modifier.fillMaxWidth().height(52.dp)) { vm.pasteKey(); text = vm.keyText }
            Tonal(stringResource(R.string.key_import), modifier = Modifier.fillMaxWidth()) { file.launch(arrayOf("*/*")) }
            vm.keyMessage?.let { Text(it, color = Green, fontSize = 14.sp) }
        }
        SectionCard("") {
            Text(stringResource(R.string.android_note), fontSize = 14.sp)
        }
    }
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun LogTab(vm: MainViewModel) {
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(Dim.cardGap)) {
        SectionCard(stringResource(R.string.activity)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.dev_mode), Modifier.weight(1f), fontSize = 17.sp)
                CompositionLocalProvider(LocalMinimumInteractiveComponentSize provides Dp.Unspecified) {
                    Switch(vm.devMode, { vm.setDev(it) })
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Tonal(stringResource(R.string.copy), modifier = Modifier.weight(1f)) { vm.copyLog() }
                Tonal(stringResource(R.string.clear), color = MaterialTheme.colorScheme.error, modifier = Modifier.weight(1f)) { vm.log.clear() }
            }
            if (vm.log.isEmpty()) Text(stringResource(R.string.log_empty), fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            else Column {
                for (line in vm.log.takeLast(40).reversed()) Text(line, fontFamily = FontFamily.Monospace, fontSize = 12.sp)
            }
        }
        SectionCard(stringResource(R.string.version)) { Text(vm.versionLabel, fontSize = 16.sp) }
    }
}
