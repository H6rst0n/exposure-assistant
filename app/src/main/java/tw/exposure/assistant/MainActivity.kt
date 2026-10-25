@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
package tw.exposure.assistant

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.*
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.*
import androidx.lifecycle.compose.*
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.*

class MainActivity: ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(statusBarStyle = androidx.activity.SystemBarStyle.dark(android.graphics.Color.TRANSPARENT), navigationBarStyle = androidx.activity.SystemBarStyle.dark(android.graphics.Color.TRANSPARENT))
        setContent { ExposureApp() }
    }
}
private val normalColors = darkColorScheme(
    primary = Color(0xFFB3DDC2), onPrimary = Color(0xFF102B1D), primaryContainer = Color(0xFF253E31), onPrimaryContainer = Color(0xFFD5EEDD),
    secondary = Color(0xFFDFBE88), background = Color(0xFF101714), surface = Color(0xFF18221D), surfaceVariant = Color(0xFF26332B),
    secondaryContainer = Color(0xFF314A3B), onSecondaryContainer = Color(0xFFD5EEDD),
    surfaceContainerLowest = Color(0xFF101714), surfaceContainerLow = Color(0xFF18221D), surfaceContainer = Color(0xFF1C2921), surfaceContainerHigh = Color(0xFF26332B), surfaceContainerHighest = Color(0xFF314037),
    onBackground = Color(0xFFE7EAE2), surfaceTint = Color(0xFFB3DDC2),
    onSurface = Color(0xFFE7EAE2), onSurfaceVariant = Color(0xFFB5BDB3), outline = Color(0xFF657669), error = Color(0xFFFFB4A9)
)
private val redColors = darkColorScheme(
    primary = Color(0xFFC5776F), onPrimary = Color(0xFF220504), primaryContainer = Color(0xFF351310), onPrimaryContainer = Color(0xFFC78378),
    secondary = Color(0xFFB77364), background = Color(0xFF0F0303), surface = Color(0xFF1B0807), surfaceVariant = Color(0xFF30100E),
    secondaryContainer = Color(0xFF351310), onSecondaryContainer = Color(0xFFC78378),
    surfaceContainerLowest = Color(0xFF0F0303), surfaceContainerLow = Color(0xFF1B0807), surfaceContainer = Color(0xFF240B09), surfaceContainerHigh = Color(0xFF30100E), surfaceContainerHighest = Color(0xFF3A1511),
    onBackground = Color(0xFFCE8C82), surfaceTint = Color(0xFFC5776F),
    onSurface = Color(0xFFCE8C82), onSurfaceVariant = Color(0xFFAA746E), outline = Color(0xFF713A33), error = Color(0xFFD97C6C)
)
@Composable
fun ExposureApp(vm: ExposureViewModel = viewModel()) {
    val settings by vm.settings.collectAsStateWithLifecycle()
    val loaded by vm.loaded.collectAsStateWithLifecycle()
    val timer by vm.timer.collectAsStateWithLifecycle()
    val message by vm.message.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val activity = context as Activity
    var showSettings by rememberSaveable { mutableStateOf(false) }
    var showStars by rememberSaveable { mutableStateOf(false) }
    var starsVisited by rememberSaveable { mutableStateOf(false) }
    var showHelp by rememberSaveable { mutableStateOf(false) }
    var timerSeconds by rememberSaveable { mutableStateOf<String?>(null) }
    var permissionEpoch by remember { mutableIntStateOf(0) }
    var notificationAsked by rememberSaveable { mutableStateOf(false) }
    val lifecycleOwner = androidx.lifecycle.compose.LocalLifecycleOwner.current
    val notifyPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { permissionEpoch++ }
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_RESUME) { permissionEpoch++; vm.reconcile() } }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
    LaunchedEffect(settings.dim, settings.brightness) {
        val params = activity.window.attributes
        params.screenBrightness = if(settings.dim) settings.brightness else -1f
        activity.window.attributes = params
    }
    DisposableEffect(activity) {
        onDispose { val old = activity.window.attributes; old.screenBrightness = -1f; activity.window.attributes = old }
    }
    LaunchedEffect(loaded, settings.page) {
        if (loaded && settings.page == 1 && !starsVisited) {
            starsVisited = true
            if (!settings.hideStars) showStars = true
        }
    }
    val lifecycleState by lifecycleOwner.lifecycle.currentStateFlow.collectAsState()
    // Keep expiration outside the lazy list: it must run even when the card is offscreen.
    LaunchedEffect(timer.id, timer.status, lifecycleState) {
        if (timer.status == "active" && lifecycleState.isAtLeast(Lifecycle.State.RESUMED)) {
            val remaining = (timer.endElapsed - SystemClock.elapsedRealtime()).coerceAtLeast(0)
            delay(remaining)
            vm.expireInForeground(timer.id)
        }
    }
    DisposableEffect(timer.status, timer.background, lifecycleState) {
        val keep = timer.status == "active" && !timer.background && lifecycleState.isAtLeast(Lifecycle.State.RESUMED)
        if (keep) activity.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        onDispose { activity.window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) }
    }
    MaterialTheme(colorScheme = if(settings.red) redColors else normalColors) {
        if (!loaded) { Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background), contentAlignment = Alignment.Center) { CircularProgressIndicator() }; return@MaterialTheme }
        val astro = settings.page == 1
        val form = if(astro) settings.astro else settings.exposure
        val result = remember(form, astro) { runCatching { calculate(form, astro) } }
        val calc = result.getOrNull()
        val snack = remember { SnackbarHostState() }
        LaunchedEffect(message) { message?.let { snack.showSnackbar(it); vm.message.value = null } }
        Scaffold(
            modifier = Modifier.testTag(if(settings.red) "theme_red" else "theme_dark"),
            containerColor = MaterialTheme.colorScheme.background,
            snackbarHost = { SnackbarHost(snack) },
            topBar = {
                TopAppBar(title = { Column { Text("曝光助手", fontWeight = FontWeight.SemiBold, fontSize = 23.sp, lineHeight = 28.sp); if(LocalDensity.current.fontScale <= 1.25f) Text("EXPOSURE COMPANION", fontSize = 9.sp, lineHeight = 12.sp, letterSpacing = 2.sp, color = MaterialTheme.colorScheme.primary) } },
                    navigationIcon = { Icon(Icons.Outlined.Camera, "曝光助手", Modifier.padding(start = 18.dp, end = 8.dp).size(28.dp), tint = MaterialTheme.colorScheme.primary) },
                    actions = {
                        IconButton(onClick = { showHelp = true }) { Icon(Icons.Outlined.Info, "使用說明") }
                        IconButton(onClick = { showSettings = true }) { Icon(Icons.Outlined.Tune, "設定與夜間模式") }
                    }, colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background))
            },
            bottomBar = {
                Column(Modifier.windowInsetsPadding(WindowInsets.navigationBars.only(WindowInsetsSides.Horizontal))) {
                    if (calc != null) Surface(color = MaterialTheme.colorScheme.primaryContainer) {
                        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(if(calc.corrected != null) "底片實拍時間" else "目標${form.solve.label}", style = MaterialTheme.typography.labelMedium)
                            Text(if(calc.corrected != null) secondsLabel(calc.corrected) else valueLabel(calc.exact, form.solve), fontWeight = FontWeight.Bold)
                        }
                    }
                    NavigationBar(containerColor = MaterialTheme.colorScheme.surface, tonalElevation = 0.dp) {
                        NavigationBarItem(selected = !astro, onClick = { vm.update { it.copy(page = 0) } }, icon = { Icon(Icons.Outlined.Camera, null) }, label = { Text("曝光換算") }, modifier = Modifier.testTag("tab_exposure"))
                        NavigationBarItem(selected = astro, onClick = { vm.update { it.copy(page = 1) } }, icon = { Icon(Icons.Outlined.AutoAwesome, null) }, label = { Text("星空攝影") }, modifier = Modifier.testTag("tab_astro"))
                    }
                }
            }
        ) { inset ->
            key(astro) {
                val listState = rememberLazyListState()
                LaunchedEffect(timer.id, timer.status) { if(timer.status == "active") listState.animateScrollToItem(0) }
                LazyColumn(Modifier.fillMaxSize().padding(inset).imePadding().testTag("main_scroll"), state = listState, contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    item {
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(if(astro) "讓星光，留下來。" else "把試拍，換成下一張。", fontSize = 21.sp, fontWeight = FontWeight.Medium)
                                Text(if(astro) "固定腳架 · 數碼相機" else "等效曝光 · ND · 膠片", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp, modifier = Modifier.padding(top = 6.dp))
                            }
                            if(astro) OutlinedButton(onClick = { showStars = true }, contentPadding = PaddingValues(horizontal = 12.dp)) { Text("500 法則") }
                        }
                    }
                    if(timer.status != "idle") item {
                        TimerCard(timer, onCancel = vm::cancelTimer)
                    }
                    item {
                        ParameterCard("01", "參考設定", "輸入試拍後，亮度合適的一張", form.reference, "ref", null, null, astro,
                            { updated -> vm.form(astro) { it.copy(reference = updated) } }) {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                TextButton(onClick = { vm.form(astro) { it.copy(reference = Inputs("2", "2", "6400")) } }, modifier = Modifier.testTag("load_sample")) { Text("載入範例") }
                                TextButton(onClick = { vm.form(astro) { it.copy(reference = Inputs()) } }) { Text("清空") }
                            }
                        }
                    }
                    item {
                        Panel {
                            SectionHeader("02", "目標設定", "選擇交給助手計算的項目")
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                val available = if(astro) listOf(Solve.SHUTTER, Solve.ISO) else Solve.entries.filterNot { form.filmMode && it == Solve.ISO }
                                available.forEach { solve -> FilterChip(selected = form.solve == solve, onClick = { vm.form(astro) { it.copy(solve = solve) } }, label = { Text("求${solve.label}") }, modifier = Modifier.testTag("solve_${solve.name}")) }
                            }
                            InputFields(form.target, "target", form.solve, calc?.exact, { updated -> vm.form(astro) { it.copy(target = updated) } })
                            if(!astro && form.solve != Solve.ND) NdField(form.target) { updated -> vm.form(astro) { it.copy(target = updated) } }
                            if(!astro && form.solve == Solve.ND) Text("ND 會以總檔數求解，其他三項由你設定。", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            OutlinedTextField(value = form.compensation, onValueChange = { v -> if(v.length <= 32) vm.form(astro) { it.copy(compensation = v) } }, label = { Text("相對參考增減曝光（檔）") }, supportingText = { Text("0 保持等效亮度；+1 亮一檔；−1 暗一檔") }, singleLine = true, modifier = Modifier.fillMaxWidth().testTag("compensation"))
                            if(!astro) {
                                HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.25f))
                                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                    Column(Modifier.weight(1f)) { Text("底片長曝光補償", fontWeight = FontWeight.Medium); Text("目標 ISO／EI 固定，由你指定", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                                    Switch(checked = form.filmMode, onCheckedChange = { enabled -> vm.form(false) { it.copy(filmMode = enabled, solve = if(enabled && it.solve == Solve.ISO) Solve.SHUTTER else it.solve) } }, modifier = Modifier.testTag("film_switch"))
                                }
                                if(form.filmMode) FilmSelector(form.filmId) { id -> vm.form(false) { it.copy(filmId = id) } }
                            }
                        }
                    }
                    item {
                        if(calc != null) ResultCard(form, calc, astro) { value -> timerSeconds = number(value) }
                        else Panel {
                            Icon(Icons.Outlined.LightMode, null, tint = MaterialTheme.colorScheme.secondary)
                            Text("準備好參考照片，就能開始。", fontWeight = FontWeight.Medium)
                            Text(result.exceptionOrNull()?.message ?: "請檢查輸入", color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.testTag("input_message"))
                            Text("不會在缺少參考曝光時猜測場景亮度。", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    item { Text("ISO 改變等效曝光亮度，不代表增加實際進光量。跨器材換算是拍攝起點，仍請以試拍結果確認。", fontSize = 12.sp, lineHeight = 19.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 4.dp, vertical = 4.dp)) }
                }
            }
        }
        if(showStars) AlertDialog(onDismissRequest = { showStars = false }, icon = { Icon(Icons.Outlined.AutoAwesome, null) }, title = { Text("避免星星拖線：500 法則") },
            text = { Column(Modifier.verticalScroll(rememberScrollState())) {
                Text(STAR_NOTICE, lineHeight = 23.sp)
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.clickable { vm.update { it.copy(hideStars = !it.hideStars) } }) {
                    Checkbox(checked = settings.hideStars, onCheckedChange = { checked -> vm.update { it.copy(hideStars = checked) } })
                    Text("下次不再自動顯示")
                }
            } }, confirmButton = { TextButton(onClick = { showStars = false }, modifier = Modifier.testTag("stars_dismiss")) { Text("我知道了") } })
        if(showHelp) AlertDialog(onDismissRequest = { showHelp = false }, title = { Text("先試拍，再換算") }, text = { Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("1. 在相同場景試拍，確認亮度合適。\n2. 輸入參考光圈、快門與 ISO。\n3. 選擇求解項目，輸入其他目標設定。\n4. 查看理論值、常用值與曝光差。")
            Text("快門以秒輸入，例如 1/125、0.5 或 120。ND 多片疊加可輸入 3 + 6（檔），或 8 + 64（倍率）。")
            Text("手機請使用可控制曝光的單張拍攝模式。HDR、夜景合成、不同影像處理及鏡頭透光率，都可能讓換算亮度與實拍有差異。")
            Text("底片 ISO／EI 是拍攝時採用的感光度設定；更改此數字不會改變已裝底片的實際感光能力。推拉沖洗需另行安排。")
            Text("底片資料：${Films.VERSION}\n${Films.SOURCE}", fontSize = 11.sp)
            Text("星空參考：Canon Academy — Astrophotography\nhttps://www.academy.canon.co.za/en/hacks-tips-tricks/astrophotography", fontSize = 11.sp)
            Text("本 App 離線運作、不控制相機、不讀取照片。版本 1.0.1", fontSize = 12.sp)
        } }, confirmButton = { TextButton(onClick = { showHelp = false }) { Text("關閉") } })
        if(showSettings) SettingsDialog(settings, vm::update) { showSettings = false }
        if(timerSeconds != null) {
            @Suppress("UNUSED_VARIABLE") val refresh = permissionEpoch
            val ready = vm.timers.backgroundAvailable(settings.sound, settings.vibration)
            val seconds = runCatching { ExposureMath.positive(timerSeconds!!, "計時秒數") }.getOrNull()
            AlertDialog(onDismissRequest = { timerSeconds = null }, title = { Text("曝光倒數") }, text = { Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(timerSeconds!!, { timerSeconds = it.take(32) }, label = { Text("計時秒數") }, supportingText = { Text("0.1 秒至 7 天；不會控制相機快門") }, singleLine = true, modifier = Modifier.testTag("timer_seconds"))
                if(timer.status == "active") Text("已有計時正在進行，請先關閉此視窗並取消原計時。", color = MaterialTheme.colorScheme.error)
                if(ready) Text("背景提醒已就緒。可鎖屏等待；聲音仍受通知設定、系統音量與勿擾模式影響。")
                else {
                    Text("背景提醒尚未就緒。前景計時會保持螢幕開啟；切換 App 或鎖屏後，不保證準時提醒。", color = MaterialTheme.colorScheme.secondary)
                    if(!vm.timers.exactAllowed() && Build.VERSION.SDK_INT >= 31) OutlinedButton(onClick = {
                        runCatching { context.startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:${context.packageName}"))) }
                            .onFailure { vm.message.value = "請到系統設定開啟曝光助手的鬧鐘與提醒權限。" }
                    }) { Text("允許精確鬧鐘") }
                    OutlinedButton(onClick = {
                        if(Build.VERSION.SDK_INT >= 33 && !vm.timers.notificationsAllowed() && !notificationAsked) { notificationAsked = true; notifyPermission.launch(Manifest.permission.POST_NOTIFICATIONS) }
                        else runCatching { context.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)) }
                    }) { Text("設定通知權限") }
                }
                Text("以你按下開始的時刻計時；請配合相機手動啟閉快門。裝置重啟會中斷計時。", style = MaterialTheme.typography.bodySmall)
            } }, confirmButton = { TextButton(enabled = seconds != null && seconds >= 0.1 && seconds <= TimerController.MAX_SECONDS && timer.status != "active", onClick = { vm.startTimer(seconds!!, ready); timerSeconds = null }, modifier = Modifier.testTag("timer_start")) { Text(if(ready) "開始倒數" else "使用前景計時") } }, dismissButton = { TextButton(onClick = { timerSeconds = null }) { Text("取消") } })
        }
    }
}

@Composable
private fun Panel(content: @Composable ColumnScope.() -> Unit) {
    Surface(shape = RoundedCornerShape(22.dp), color = MaterialTheme.colorScheme.surface, border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.18f))) {
        Column(Modifier.fillMaxWidth().padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp), content = content)
    }
}
@Composable
private fun SectionHeader(index: String, title: String, subtitle: String) {
    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(index, fontFamily = FontFamily.Monospace, color = MaterialTheme.colorScheme.secondary, fontSize = 13.sp, modifier = Modifier.padding(top = 4.dp))
        Column { Text(title, fontSize = 18.sp, fontWeight = FontWeight.SemiBold); Text(subtitle, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp, modifier = Modifier.padding(top = 3.dp)) }
    }
}
@Composable
private fun ParameterCard(index: String, title: String, subtitle: String, inputs: Inputs, prefix: String, solve: Solve?, exact: Double?, astro: Boolean, onChange: (Inputs) -> Unit, footer: @Composable () -> Unit) {
    Panel { SectionHeader(index,title,subtitle); InputFields(inputs,prefix,solve,exact,onChange); if(!astro) NdField(inputs,onChange); footer() }
}
@Composable
private fun InputFields(inputs: Inputs, prefix: String, solve: Solve?, exact: Double?, onChange: (Inputs) -> Unit) {
    val large = LocalDensity.current.fontScale > 1.25f
    val content: @Composable (Solve, String, String, (String) -> Unit, Modifier) -> Unit = { field, label, value, setter, modifier ->
        val solved = solve == field
        NumericField(label, if(solved) exact?.let { number(it) } ?: "" else value, setter, field, modifier.testTag("${prefix}_${field.name.lowercase()}"), solved)
    }
    if(large) Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        content(Solve.APERTURE,"光圈 f/",inputs.aperture,{ onChange(inputs.copy(aperture = it)) },Modifier.fillMaxWidth())
        content(Solve.SHUTTER,"快門（秒）",inputs.shutter,{ onChange(inputs.copy(shutter = it)) },Modifier.fillMaxWidth())
        content(Solve.ISO,"ISO / EI",inputs.iso,{ onChange(inputs.copy(iso = it)) },Modifier.fillMaxWidth())
    } else Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        content(Solve.APERTURE,"光圈 f/",inputs.aperture,{ onChange(inputs.copy(aperture = it)) },Modifier.weight(1f))
        content(Solve.SHUTTER,"快門（秒）",inputs.shutter,{ onChange(inputs.copy(shutter = it)) },Modifier.weight(1f))
        content(Solve.ISO,"ISO / EI",inputs.iso,{ onChange(inputs.copy(iso = it)) },Modifier.weight(1f))
    }
}
@Composable
private fun NumericField(label: String, value: String, change: (String) -> Unit, type: Solve, modifier: Modifier, solved: Boolean) {
    var showPresets by remember { mutableStateOf(false) }
    Column(modifier) {
        OutlinedTextField(value, { if(it.length <= 48) change(it) }, label = { Text(label, fontSize = 12.sp) }, placeholder = { Text(if(solved) "待計算" else "輸入", fontSize = 13.sp) }, readOnly = solved, singleLine = true,
            textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace, fontSize = 16.sp), modifier = Modifier.fillMaxWidth(),
            colors = OutlinedTextFieldDefaults.colors(focusedTextColor = if(solved) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface, unfocusedTextColor = if(solved) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface))
        if(solved) Text("自動計算", fontSize = 11.sp, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(top = 8.dp, start = 4.dp))
        else TextButton(onClick = { showPresets = true }, contentPadding = PaddingValues(horizontal = 4.dp), modifier = Modifier.heightIn(min = 40.dp)) { Text("常用值", fontSize = 12.sp); Icon(Icons.Outlined.ExpandMore, null, Modifier.size(16.dp)) }
    }
    if(showPresets) {
        val values = when(type) { Solve.APERTURE -> ExposureMath.apertures; Solve.ISO -> ExposureMath.isos; else -> ExposureMath.shutters }
        AlertDialog(onDismissRequest = { showPresets = false }, title = { Text("選擇${type.label}") }, text = {
            LazyColumn(Modifier.heightIn(max = 360.dp)) { items(values.size) { index ->
                val v = values[index]
                TextButton(onClick = { change(if(type == Solve.SHUTTER && v < 0.5) "1/${number(1/v)}" else number(v)); showPresets = false }, modifier = Modifier.fillMaxWidth()) { Text(valueLabel(v,type)) }
            } }
        }, confirmButton = { TextButton(onClick = { showPresets = false }) { Text("關閉") } })
    }
}
@Composable
private fun NdField(inputs: Inputs, onChange: (Inputs) -> Unit) {
    var open by rememberSaveable { mutableStateOf(false) }
    Column {
        TextButton(onClick = { open = !open }, contentPadding = PaddingValues(0.dp)) { Icon(Icons.Outlined.FilterAlt, null, Modifier.size(17.dp)); Spacer(Modifier.width(6.dp)); Text("減光鏡 ND · ${inputs.nd} ${inputs.unit.label}", fontSize = 12.sp); Icon(if(open) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore, null) }
        if(open) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                NdUnit.entries.forEach { unit -> FilterChip(selected = unit == inputs.unit, onClick = {
                    val stops = runCatching { ExposureMath.nd(inputs.nd, inputs.unit) }.getOrNull()
                    val converted = stops?.let { when(unit) { NdUnit.STOPS -> it; NdUnit.FACTOR -> 2.0.pow(it); NdUnit.DENSITY -> it * log10(2.0) } }
                    onChange(inputs.copy(unit = unit, nd = converted?.toString() ?: inputs.nd))
                }, label = { Text(unit.label) }) }
            }
            OutlinedTextField(inputs.nd, { if(it.length <= 120) onChange(inputs.copy(nd = it)) }, label = { Text("ND ${inputs.unit.label}") }, supportingText = { Text(when(inputs.unit) { NdUnit.STOPS -> "多片：3 + 6 → 9 檔；無濾鏡填 0"; NdUnit.FACTOR -> "多片：8 + 64 → 512 倍；無濾鏡填 1"; NdUnit.DENSITY -> "多片：0.9 + 1.8 → 密度 2.7；無濾鏡填 0" }) }, singleLine = true, modifier = Modifier.fillMaxWidth())
            runCatching { ExposureMath.nd(inputs.nd, inputs.unit) }.getOrNull()?.let { Text("合計 ${number(it)} 檔 · ${number(2.0.pow(it))} 倍 · 密度 ${number(it*log10(2.0))}", fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
    }
}
@Composable
private fun FilmSelector(id: String, select: (String) -> Unit) {
    var show by remember { mutableStateOf(false) }
    OutlinedButton(onClick = { show = true }, modifier = Modifier.fillMaxWidth().testTag("film_selector")) { Text(Films.find(id)?.name ?: "其他底片（無補償資料）"); Spacer(Modifier.weight(1f)); Icon(Icons.Outlined.ExpandMore, null) }
    Text("${Films.VERSION}\n僅求快門時套用補償；超長曝光仍需試拍確認。", fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
    if(show) AlertDialog(onDismissRequest = { show = false }, title = { Text("選擇底片") }, text = { LazyColumn(Modifier.heightIn(max = 360.dp)) {
        items(Films.all.size) { index -> val film = Films.all[index]; TextButton(onClick = { select(film.id); show = false }, modifier = Modifier.fillMaxWidth()) { Text("${film.name} · P = ${film.exponent}") } }
        item { TextButton(onClick = { select("unknown"); show = false }) { Text("其他底片（無補償資料）") } }
    } }, confirmButton = { TextButton(onClick = { show = false }) { Text("關閉") } })
}
@Composable
private fun ResultCard(form: FormState, calc: Calculation, astro: Boolean, startTimer: (Double) -> Unit) {
    Surface(color = MaterialTheme.colorScheme.primaryContainer, shape = RoundedCornerShape(22.dp)) {
        Column(Modifier.fillMaxWidth().padding(22.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("03  ／  換算結果", letterSpacing = 1.sp, fontSize = 12.sp, color = MaterialTheme.colorScheme.primary)
            Text(if(calc.corrected != null) "理論曝光時間" else "目標${form.solve.label}", fontSize = 13.sp)
            Text(valueLabel(calc.exact,form.solve), fontSize = 34.sp, lineHeight = 41.sp, fontWeight = FontWeight.Light, fontFamily = FontFamily.Monospace, modifier = Modifier.testTag("exact_result"))
            if(form.solve == Solve.ND && calc.exact < 0) Text("需要增加 ${number(-calc.exact)} 檔曝光。移除 ND 或調整光圈、快門、ISO；沒有負檔減光鏡。")
            else if(form.solve == Solve.ND) Text("總倍率 ${number(2.0.pow(calc.exact))}× · 光學密度 ${number(calc.exact*log10(2.0))}")
            calc.common?.let { common ->
                val diff = calc.difference ?: 0.0
                val wording = if(abs(diff) < 0.00005) "與理論值相同" else "${if(diff > 0) "亮" else "暗"} ${number(abs(diff))} 檔"
                Text("${if(form.solve == Solve.SHUTTER && common > 30) "B 門取整參考" else "常用設定參考"}：${valueLabel(common,form.solve)}\n$wording", lineHeight = 22.sp)
            } ?: if(!(form.solve == Solve.ND && calc.exact < 0)) Text("結果超出內建常用值範圍，請確認器材可用設定。") else Unit
            if(form.filmMode && !astro) {
                HorizontalDivider(color = MaterialTheme.colorScheme.primary.copy(alpha = 0.2f))
                if(calc.corrected != null) {
                    Text("${calc.film?.name} · 補償後實拍", fontSize = 13.sp)
                    Text(secondsLabel(calc.corrected), fontWeight = FontWeight.SemiBold, fontSize = 26.sp, modifier = Modifier.testTag("corrected_result"))
                    Text(if(calc.exact <= 1) "不超過 1 秒，依原廠規則不需補償。" else "以未取整的理論秒數套用 t^${calc.film?.exponent}，只補償一次。", fontSize = 12.sp)
                } else Text(if(calc.film == null) "此底片尚無補償資料；目前只顯示理論換算。" else "目前為理論反算，未包含底片長曝光補償。求快門時才套用補償。", fontSize = 12.sp)
            }
            val time = calc.corrected ?: calc.targetSeconds
            Button(onClick = { startTimer(time) }, enabled = time in 0.1..TimerController.MAX_SECONDS, modifier = Modifier.fillMaxWidth().testTag("open_timer")) {
                Icon(Icons.Outlined.Timer, null, Modifier.size(19.dp)); Spacer(Modifier.width(8.dp)); Text("曝光倒數 · ${secondsLabel(time)}")
            }
            if(form.solve == Solve.SHUTTER && calc.corrected == null && calc.common != null && abs(calc.common-calc.exact) > 0.00001) TextButton(onClick = { startTimer(calc.common) }, enabled = calc.common in 0.1..TimerController.MAX_SECONDS) { Text("以常用時間計時：${secondsLabel(calc.common)}") }
            if(time !in 0.1..TimerController.MAX_SECONDS) Text("此結果不在倒數範圍內（0.1 秒至 7 天）。", fontSize = 12.sp)
        }
    }
}
@Composable
private fun CountdownText(endElapsed: Long) {
    var seconds by remember(endElapsed) {
        mutableLongStateOf(ceil((endElapsed - SystemClock.elapsedRealtime()).coerceAtLeast(0) / 1000.0).toLong())
    }
    val owner = androidx.lifecycle.compose.LocalLifecycleOwner.current
    LaunchedEffect(endElapsed, owner) {
        owner.lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            while (isActive) {
                val remaining = (endElapsed - SystemClock.elapsedRealtime()).coerceAtLeast(0)
                seconds = ceil(remaining / 1000.0).toLong()
                if (remaining == 0L) break
                // Wake at the next displayed-second boundary, without refreshing the form.
                delay(((remaining - 1) % 1000) + 1)
            }
        }
    }
    Text(durationLabel(seconds), fontSize = 32.sp, fontFamily = FontFamily.Monospace, modifier = Modifier.testTag("countdown"))
}

@Composable
private fun TimerCard(timer: TimerState, onCancel: () -> Unit) {
    Panel {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(Icons.Outlined.Timer, null, tint = MaterialTheme.colorScheme.secondary)
            Text(when(timer.status) { "active" -> "曝光倒數中"; "completed" -> "曝光時間已到"; else -> "計時已中斷" }, fontWeight = FontWeight.SemiBold)
        }
        if(timer.status == "active") {
            CountdownText(timer.endElapsed)
            Text(if(timer.background) "背景提醒已排程，可鎖屏。" else "僅前景計時：請保持 App 開啟及螢幕亮起。", fontSize = 12.sp, color = MaterialTheme.colorScheme.secondary)
            OutlinedButton(onClick = onCancel, modifier = Modifier.testTag("cancel_timer")) { Text("取消計時") }
        } else {
            Text(if(timer.status == "completed") "請手動關閉相機快門。" else "裝置曾重新啟動，請確認相機並重新安排曝光。")
            TextButton(onClick = onCancel) { Text("清除提示") }
        }
    }
}
@Composable
private fun SettingsDialog(settings: AppSettings, update: ((AppSettings) -> AppSettings) -> Unit, close: () -> Unit) {
    AlertDialog(onDismissRequest = close, title = { Text("現場設定") }, text = { Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SettingSwitch("夜間紅色介面", settings.red) { checked -> update { it.copy(red = checked) } }
        SettingSwitch("只調暗這個 App", settings.dim) { checked -> update { it.copy(dim = checked) } }
        if(settings.dim) { Text("視窗亮度 ${round(settings.brightness*100).toInt()}%"); Slider(settings.brightness, { v -> update { it.copy(brightness = v) } }, valueRange = 0.01f..1f) }
        HorizontalDivider()
        SettingSwitch("計時結束聲音", settings.sound) { checked -> update { it.copy(sound = checked) } }
        SettingSwitch("計時結束震動", settings.vibration) { checked -> update { it.copy(vibration = checked) } }
        Text("變更僅套用到下一次計時。實際提醒仍受手機音量、勿擾模式與通知設定影響。", fontSize = 12.sp)
        HorizontalDivider()
        SettingSwitch("不自動顯示 500 法則", settings.hideStars) { checked -> update { it.copy(hideStars = checked) } }
        Text("所有設定僅保存在這支手機，不需要網路。", fontSize = 12.sp)
    } }, confirmButton = { TextButton(onClick = close) { Text("完成") } })
}
@Composable
private fun SettingSwitch(label: String, checked: Boolean, change: (Boolean) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) { Text(label, Modifier.weight(1f)); Switch(checked, change) }
}
