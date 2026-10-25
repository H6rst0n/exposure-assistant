package tw.exposure.assistant

import java.util.Locale
import kotlin.math.*

enum class Solve(val label: String) { SHUTTER("快門"), APERTURE("光圈"), ISO("ISO"), ND("ND") }
enum class NdUnit(val label: String) { STOPS("檔數"), FACTOR("倍率"), DENSITY("光學密度") }
data class Exposure(val aperture: Double, val seconds: Double, val iso: Double, val nd: Double = 0.0)
data class Film(val id: String, val name: String, val exponent: Double)
object Films {
    const val SOURCE = "https://www.ilfordphoto.com/amfile/file/download/file/1964/product/698/"
    const val VERSION = "ILFORD / HARMAN · Dec 2023"
    val all = listOf(
        Film("sfx", "SFX 200", 1.43), Film("panf", "Pan F Plus", 1.33),
        Film("d100", "DELTA 100", 1.26), Film("d400", "DELTA 400", 1.41),
        Film("d3200", "DELTA 3200", 1.33), Film("fp4", "FP4 Plus", 1.26),
        Film("hp5", "HP5 Plus", 1.31), Film("xp2", "XP2 Super", 1.31),
        Film("ortho", "ORTHO Plus", 1.25), Film("k100", "Kentmere 100", 1.26),
        Film("k400", "Kentmere 400", 1.30)
    )
    fun find(id: String) = all.find { it.id == id }
    fun corrected(seconds: Double, film: Film): Double {
        require(seconds.isFinite() && seconds > 0) { "曝光時間必須大於 0" }
        return (if (seconds <= 1) seconds else seconds.pow(film.exponent)).also {
            require(it.isFinite()) { "補償時間超出可計算範圍" }
        }
    }
}
object ExposureMath {
    fun positive(text: String, name: String): Double {
        val parts = text.trim().split('/')
        val value = when (parts.size) {
            1 -> parts[0].toDoubleOrNull()
            2 -> {
                val a = parts[0].trim().toDoubleOrNull()
                val b = parts[1].trim().toDoubleOrNull()
                if (a == null || b == null || a <= 0 || b <= 0) null else a / b
            }
            else -> null
        }
        require(value != null && value.isFinite() && value > 0) { "$name 請輸入大於 0 的數值（快門可用 1/125）" }
        return value
    }
    fun compensation(text: String): Double {
        val v = text.trim().toDoubleOrNull()
        require(v != null && v.isFinite() && abs(v) <= 100) { "曝光補償請輸入 −100 到 +100 檔" }
        return v
    }
    /** '+' explicitly means stacked filters, in the selected unit. */
    fun nd(text: String, unit: NdUnit): Double {
        require(text.isNotBlank()) { "請輸入 ND；無濾鏡請填 0 檔或 1 倍" }
        val sum = text.split('+').sumOf { part ->
            val v = part.trim().toDoubleOrNull()
            require(v != null && v.isFinite()) { "ND 請輸入數字，多片以 + 相連" }
            when (unit) {
                NdUnit.STOPS -> { require(v >= 0) { "ND 檔數不可小於 0" }; v }
                NdUnit.FACTOR -> { require(v >= 1) { "ND 倍率至少為 1" }; log2(v) }
                NdUnit.DENSITY -> { require(v >= 0) { "光學密度不可小於 0" }; v / log10(2.0) }
            }
        }
        require(sum.isFinite() && sum <= 100) { "ND 總量請勿超過 100 檔" }
        return sum
    }
    fun level(e: Exposure): Double = log2(e.seconds) + log2(e.iso) - 2 * log2(e.aperture) - e.nd
    fun solve(reference: Exposure, target: Exposure, what: Solve, compensation: Double): Double {
        listOf(reference.aperture, reference.seconds, reference.iso, target.aperture, target.seconds, target.iso).forEach {
            require(it.isFinite() && it > 0) { "光圈、快門與 ISO 必須大於 0" }
        }
        require(reference.nd.isFinite() && target.nd.isFinite() && reference.nd >= 0 && target.nd >= 0)
        require(compensation.isFinite())
        val desired = level(reference) + compensation
        val logResult = when (what) {
            Solve.SHUTTER -> desired - log2(target.iso) + 2 * log2(target.aperture) + target.nd
            Solve.ISO -> desired - log2(target.seconds) + 2 * log2(target.aperture) + target.nd
            Solve.APERTURE -> (log2(target.seconds) + log2(target.iso) - target.nd - desired) / 2
            Solve.ND -> return (level(target.copy(nd = 0.0)) - desired).also { require(it.isFinite() && abs(it) <= 100) { "ND 結果超出 ±100 檔，請縮小參數差距" } }
        }
        return 2.0.pow(logResult).also { require(it.isFinite() && it > 0) { "結果超出可計算範圍，請縮小參數差距" } }
    }
    val shutters = listOf(8000,6400,5000,4000,3200,2500,2000,1600,1250,1000,800,640,500,400,320,250,200,160,125,100,80,60,50,40,30,25,20,15,13,10,8,6,5,4,3,2).map { 1.0 / it } + listOf(0.6,0.8,1.0,1.3,1.6,2.0,2.5,3.2,4.0,5.0,6.0,8.0,10.0,13.0,15.0,20.0,25.0,30.0)
    val apertures = listOf(1.0,1.2,1.4,1.6,1.8,2.0,2.2,2.5,2.8,3.2,3.5,4.0,4.5,5.0,5.6,6.3,7.1,8.0,9.0,10.0,11.0,13.0,14.0,16.0,18.0,20.0,22.0,25.0,29.0,32.0,36.0,40.0,45.0,51.0,57.0,64.0)
    val isos = listOf(25,32,40,50,64,80,100,125,160,200,250,320,400,500,640,800,1000,1250,1600,2000,2500,3200,4000,5000,6400,8000,10000,12800,16000,20000,25600,32000,40000,51200,64000,80000,102400,128000,160000,204800).map(Int::toDouble)
    fun common(value: Double, what: Solve): Double? {
        if (what == Solve.ND) return if (value < 0) null else round(value)
        if (what == Solve.SHUTTER && value > 30) return if(value <= 604800) value.roundToLong().coerceAtLeast(1).toDouble() else null
        val choices = when (what) { Solve.SHUTTER -> shutters; Solve.ISO -> isos; else -> apertures }
        if (value < choices.first() || value > choices.last()) return null
        return choices.minBy { abs(log2(it / value)) }
    }
    fun roundingStops(exact: Double, common: Double, what: Solve): Double = when (what) {
        Solve.APERTURE -> -2 * log2(common / exact)
        Solve.ND -> exact - common
        else -> log2(common / exact)
    }
}
fun number(value: Double): String = when {
    value == 0.0 -> "0"
    abs(value) >= 1e8 || abs(value) < 0.0001 -> String.format(Locale.US, "%.4g", value)
    else -> String.format(Locale.US, "%.4f", value).trimEnd('0').trimEnd('.')
}
fun secondsLabel(value: Double): String = if (value < 1 && (1 / value).isFinite()) "1/${number(1 / value)} 秒" else "${number(value)} 秒"
fun valueLabel(value: Double, solve: Solve): String = when (solve) {
    Solve.SHUTTER -> secondsLabel(value)
    Solve.APERTURE -> "f/${number(value)}"
    Solve.ISO -> "ISO ${number(value)}"
    Solve.ND -> "${number(value)} 檔"
}
fun durationLabel(seconds: Long): String {
    val s = seconds.coerceAtLeast(0)
    return String.format(Locale.US, "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
}
const val STAR_NOTICE = "固定腳架、未使用追蹤設備時，可用以下方式粗估曝光時間：\n\n曝光秒數 ≈ 500 ÷ 全片幅等效焦距\n\n全片幅使用 50 mm，約為 10 秒。\nAPS-C 裁切倍率 1.5×、使用 50 mm 時，約為 6.7 秒。\n\n這是經驗估算，不是保證不拖線的硬性極限。高像素相機或放大檢視可能需要更短曝光；建議試拍後放大檢查星點。\n\n這項提醒不會更改你的快門設定。"
