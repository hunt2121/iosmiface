package com.bandface.app

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Subject
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

class MainActivity : ComponentActivity() {
    private val vm: MainViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { App(vm) }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun App(vm: MainViewModel) {
    val dark = isSystemInDarkTheme()
    val ctx = LocalContext.current
    val scheme = if (Build.VERSION.SDK_INT >= 31) {
        if (dark) dynamicDarkColorScheme(ctx) else dynamicLightColorScheme(ctx)
    } else if (dark) darkColorScheme() else lightColorScheme()
    MaterialTheme(colorScheme = scheme) {
        var tab by remember { mutableIntStateOf(0) }
        Scaffold(
            bottomBar = {
                NavigationBar {
                    NavigationBarItem(tab == 0, { tab = 0 }, { Icon(Icons.Filled.Schedule, null) }, label = { Text(stringResource(R.string.tab_faces)) })
                    NavigationBarItem(tab == 1, { tab = 1 }, { Icon(Icons.Filled.Key, null) }, label = { Text(stringResource(R.string.tab_key)) })
                    NavigationBarItem(tab == 2, { tab = 2 }, { Icon(Icons.Filled.Subject, null) }, label = { Text(stringResource(R.string.tab_log)) })
                }
            },
        ) { pad ->
            Column(Modifier.padding(pad).fillMaxSize()) {
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

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(stringResource(R.string.band), style = MaterialTheme.typography.titleMedium)
        Text(vm.connectedName?.let { stringResource(R.string.connected, it) } ?: stringResource(R.string.not_connected))
        OutlinedButton({ permLauncher.launch(permissions) }, enabled = !vm.busy) { Text(stringResource(R.string.scan)) }
        for (d in vm.devices) {
            Card(Modifier.fillMaxWidth()) {
                TextButton({ vm.connect(d) }, Modifier.fillMaxWidth(), enabled = !vm.busy) {
                    Column(Modifier.fillMaxWidth()) {
                        Text(d.name)
                        Text(d.address, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }

        Text(stringResource(R.string.tab_faces), style = MaterialTheme.typography.titleMedium)
        OutlinedButton({ picker.launch(arrayOf("*/*")) }, enabled = !vm.busy) { Text(stringResource(R.string.pick_face)) }
        Text(vm.faceName ?: stringResource(R.string.no_face))
        Button({ vm.install() }, enabled = !vm.busy && vm.face != null) { Text(stringResource(R.string.install)) }
        vm.progress?.let { LinearProgressIndicator(progress = { it }, modifier = Modifier.fillMaxWidth()) }
        vm.status?.let { Text(it) }
    }
}

@Composable
fun KeyTab(vm: MainViewModel) {
    var text by remember { mutableStateOf(vm.keyText) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) { vm.importKey(uri); text = vm.keyText }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(stringResource(R.string.key_title), style = MaterialTheme.typography.titleMedium)
        OutlinedTextField(text, { text = it }, Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.key_hint)) }, singleLine = true)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button({ vm.saveKey(text) }) { Text(stringResource(R.string.tab_key)) }
            OutlinedButton({ picker.launch(arrayOf("*/*")) }) { Text(stringResource(R.string.key_import)) }
        }
        vm.status?.let { Text(it) }
        Text(stringResource(R.string.key_note), style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
fun LogTab(vm: MainViewModel) {
    val version = remember {
        runCatching { "1.1 (" + (android.os.Build.VERSION.SDK_INT) + ")" }.getOrDefault("1.1")
    }
    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Text(stringResource(R.string.version) + ": 1.1", style = MaterialTheme.typography.titleMedium)
        TextButton({ vm.log.clear() }) { Text(stringResource(R.string.clear)) }
        if (vm.log.isEmpty()) Text(stringResource(R.string.log_empty))
        LazyColumn {
            items(vm.log.reversed()) { Text(it, fontFamily = FontFamily.Monospace, fontSize = 12.sp) }
        }
    }
}
