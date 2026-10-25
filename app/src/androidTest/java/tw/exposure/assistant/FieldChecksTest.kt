package tw.exposure.assistant

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.flow.first
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class FieldChecksTest {
    @get:Rule val rule = createAndroidComposeRule<MainActivity>()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val device get() = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
    private val repository get() = Repository(context)
    private val controller get() = TimerController(context,repository)
    private fun update(block: (AppSettings)->AppSettings) {
        rule.activityRule.scenario.onActivity { ViewModelProvider(it)[ExposureViewModel::class.java].update(block) }
        rule.waitForIdle()
    }
    @Before fun reset() {
        device.wakeUp(); device.pressMenu()
        runBlocking { controller.cancel() }
        rule.waitUntil(60000) { rule.onAllNodesWithTag("main_scroll").fetchSemanticsNodes().isNotEmpty() }
        update { AppSettings(hideStars=true) }
    }
    private fun sample() = update { it.copy(exposure=FormState(reference=Inputs("2","2","6400"))) }
    private fun scroll(tag: String) = rule.onNodeWithTag("main_scroll").performScrollToNode(hasTestTag(tag))
    private fun capture(name: String) {
        rule.mainClock.advanceTimeByFrame()
        rule.waitForIdle()
        device.waitForIdle()
        Thread.sleep(700) // Allow the software emulator compositor to present the committed frame.
        val folder = File(context.filesDir,"previews")
        folder.mkdirs()
        assertTrue(device.takeScreenshot(File(folder,name)))
    }
    @Test fun screenshotsNormalNightAndStarNotice() {
        sample()
        rule.onNodeWithTag("ref_aperture").assertIsDisplayed()
        capture("01-exposure.png")
        scroll("exact_result")
        rule.onNodeWithTag("exact_result").assertTextEquals("32 秒")
        capture("02-result.png")
        update { it.copy(red=true) }
        rule.waitUntil(30000) { rule.onAllNodesWithTag("theme_red").fetchSemanticsNodes().isNotEmpty() }
        capture("03-night.png")
        update { it.copy(red=false,page=1) }
        rule.waitUntil(30000) { rule.onAllNodesWithTag("theme_dark").fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithText("500 法則").performClick()
        rule.onNodeWithText("避免星星拖線：500 法則").assertExists()
        capture("04-stars.png")
        rule.onNodeWithTag("stars_dismiss").performClick()
    }
    @Test fun largerTextAndLandscapeRemainOperable() {
        sample()
        try {
            device.executeShellCommand("settings put system font_scale 1.5")
            rule.activityRule.scenario.recreate()
            rule.waitUntil(60000) { rule.onAllNodesWithTag("main_scroll").fetchSemanticsNodes().isNotEmpty() }
            scroll("ref_shutter")
            rule.onNodeWithTag("ref_shutter").assertIsDisplayed()
            scroll("exact_result")
            rule.onNodeWithTag("exact_result").assertTextEquals("32 秒")
            capture("05-large-text.png")
            device.setOrientationLeft()
            rule.waitUntil(30000) { rule.activity.resources.configuration.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE }
            rule.waitForIdle()
            scroll("open_timer")
            rule.onNodeWithTag("open_timer").performScrollTo()
            rule.onNodeWithTag("open_timer").assertIsDisplayed()
            capture("06-landscape.png")
        } finally { device.setOrientationNatural(); device.unfreezeRotation(); device.executeShellCommand("settings put system font_scale 1.0") }
    }
    private fun setNotifications(enabled: Boolean) {
        device.executeShellCommand("am start -W -a android.settings.APP_NOTIFICATION_SETTINGS --es android.provider.extra.APP_PACKAGE tw.exposure.assistant")
        val toggle = device.wait(Until.findObject(By.res("com.android.settings:id/switch_widget")), 30000)
        assertNotNull("Android 11 app notification switch", toggle)
        if(toggle.isChecked != enabled) toggle.click()
        device.executeShellCommand("am start -W -n tw.exposure.assistant/.MainActivity")
    }
    @Test fun deniedNotificationExplicitlyUsesForeground() {
        sample()
        try {
            setNotifications(false)
            rule.waitUntil(15000) { !controller.notificationsAllowed() }
            scroll("open_timer")
            rule.onNodeWithTag("open_timer").performClick()
            rule.onNodeWithText("使用前景計時").assertExists()
            rule.onNodeWithTag("timer_seconds").performTextReplacement("2")
            rule.onNodeWithTag("timer_start").performClick()
            rule.waitUntil(30000) { runBlocking { repository.timer.first().status == "completed" } }
            assertFalse(runBlocking { repository.timer.first().background })
        } finally { setNotifications(true) }
    }
}
