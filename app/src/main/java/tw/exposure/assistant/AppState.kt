package tw.exposure.assistant

import android.app.Application
import android.content.Context
import androidx.datastore.preferences.core.*
import androidx.datastore.preferences.preferencesDataStore
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import org.json.JSONObject

private val Context.preferences by preferencesDataStore("exposure_settings")
data class Inputs(val aperture: String = "", val shutter: String = "", val iso: String = "", val nd: String = "0", val unit: NdUnit = NdUnit.STOPS)
data class FormState(
    val reference: Inputs = Inputs(), val target: Inputs = Inputs("2", "2", "400"),
    val solve: Solve = Solve.SHUTTER, val compensation: String = "0",
    val filmMode: Boolean = false, val filmId: String = "hp5"
)
data class AppSettings(
    val exposure: FormState = FormState(), val astro: FormState = FormState(),
    val red: Boolean = false, val dim: Boolean = false, val brightness: Float = 0.15f,
    val hideStars: Boolean = false, val page: Int = 0, val sound: Boolean = true, val vibration: Boolean = true
)
data class Calculation(val exact: Double, val common: Double?, val difference: Double?, val corrected: Double?, val film: Film?, val targetSeconds: Double)
fun calculate(form: FormState, astro: Boolean): Calculation {
    fun parse(input: Inputs, target: Boolean): Exposure {
        val what = if (target) form.solve else null
        val label = if (target) "目標" else "參考"
        return Exposure(
            if (what == Solve.APERTURE) 1.0 else ExposureMath.positive(input.aperture, "${label}光圈"),
            if (what == Solve.SHUTTER) 1.0 else ExposureMath.positive(input.shutter, "${label}快門"),
            if (what == Solve.ISO) 1.0 else ExposureMath.positive(input.iso, "${label} ISO"),
            if (astro || what == Solve.ND) 0.0 else ExposureMath.nd(input.nd, input.unit)
        )
    }
    val reference = parse(form.reference, false)
    val target = parse(form.target, true)
    val exact = ExposureMath.solve(reference, target, form.solve, ExposureMath.compensation(form.compensation))
    val common = ExposureMath.common(exact, form.solve)
    val film = if (form.filmMode && !astro) Films.find(form.filmId) else null
    val corrected = if (film != null && form.solve == Solve.SHUTTER) Films.corrected(exact, film) else null
    return Calculation(exact, common, common?.let { ExposureMath.roundingStops(exact, it, form.solve) }, corrected, film,
        if (form.solve == Solve.SHUTTER) exact else target.seconds)
}
private fun Inputs.json() = JSONObject().put("aperture", aperture).put("shutter", shutter).put("iso", iso).put("nd", nd).put("unit", unit.name)
private fun JSONObject.inputs() = Inputs(optString("aperture"), optString("shutter"), optString("iso"), optString("nd", "0"), runCatching { NdUnit.valueOf(optString("unit")) }.getOrDefault(NdUnit.STOPS))
private fun FormState.json() = JSONObject().put("reference", reference.json()).put("target", target.json()).put("solve", solve.name).put("compensation", compensation).put("filmMode", filmMode).put("filmId", filmId)
private fun JSONObject.form(): FormState = FormState(
    optJSONObject("reference")?.inputs() ?: Inputs(), optJSONObject("target")?.inputs() ?: Inputs("2", "2", "400"),
    runCatching { Solve.valueOf(optString("solve")) }.getOrDefault(Solve.SHUTTER), optString("compensation", "0"), optBoolean("filmMode"), optString("filmId", "hp5")
)
private fun AppSettings.encode() = JSONObject().put("exposure", exposure.json()).put("astro", astro.json()).put("red", red).put("dim", dim).put("brightness", brightness.toDouble()).put("hideStars", hideStars).put("page", page).put("sound", sound).put("vibration", vibration).toString()
private fun decode(text: String?): AppSettings = runCatching {
    val j = JSONObject(text ?: "{}")
    AppSettings(j.optJSONObject("exposure")?.form() ?: FormState(), j.optJSONObject("astro")?.form() ?: FormState(), j.optBoolean("red"), j.optBoolean("dim"), j.optDouble("brightness", 0.15).toFloat().coerceIn(0.01f, 1f), j.optBoolean("hideStars"), j.optInt("page").coerceIn(0,1), j.optBoolean("sound", true), j.optBoolean("vibration", true))
}.getOrDefault(AppSettings())
class Repository(context: Context) {
    private val store = context.applicationContext.preferences
    private val settingsKey = stringPreferencesKey("settings_v1")
    private val timerKey = stringPreferencesKey("timer_v1")
    val settings = store.data.map { decode(it[settingsKey]) }
    val timer = store.data.map { TimerState.decode(it[timerKey]) }
    suspend fun save(settings: AppSettings) { store.edit { it[settingsKey] = settings.encode() } }
    suspend fun changeTimer(transform: (TimerState) -> TimerState): TimerState {
        var result = TimerState()
        store.edit { prefs -> result = transform(TimerState.decode(prefs[timerKey])); prefs[timerKey] = result.encode() }
        return result
    }
}
class ExposureViewModel(app: Application): AndroidViewModel(app) {
    val repository = Repository(app)
    val timers = TimerController(app, repository)
    private val _settings = MutableStateFlow(AppSettings())
    val settings = _settings.asStateFlow()
    private val _loaded = MutableStateFlow(false)
    val loaded = _loaded.asStateFlow()
    val timer = repository.timer.stateIn(viewModelScope, SharingStarted.Eagerly, TimerState())
    val message = MutableStateFlow<String?>(null)
    private val saves = Channel<AppSettings>(Channel.CONFLATED)
    init {
        viewModelScope.launch {
            runCatching { repository.settings.first() }.onSuccess { _settings.value = it }
                .onFailure { message.value = "無法讀取已儲存設定，暫以預設值開啟。" }
            _loaded.value = true
            for (snapshot in saves) runCatching { repository.save(snapshot) }.onFailure { message.value = "設定儲存失敗，請確認儲存空間。" }
        }
        viewModelScope.launch { timers.checkBoot() }
    }
    fun update(transform: (AppSettings) -> AppSettings) {
        if (!_loaded.value) return
        _settings.update(transform)
        saves.trySend(_settings.value)
    }
    fun form(astro: Boolean, transform: (FormState) -> FormState) = update { if (astro) it.copy(astro = transform(it.astro)) else it.copy(exposure = transform(it.exposure)) }
    fun startTimer(seconds: Double, background: Boolean) {
        viewModelScope.launch {
            runCatching { timers.start(seconds, background, settings.value.sound, settings.value.vibration) }
                .onFailure { message.value = it.message ?: "無法啟動計時" }
        }
    }
    fun cancelTimer() { viewModelScope.launch { timers.cancel() } }
    fun expireInForeground(id: String) { viewModelScope.launch { timers.finish(id, true) } }
    fun reconcile() { viewModelScope.launch { timers.reconcile() } }
}
