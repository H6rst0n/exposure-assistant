package tw.exposure.assistant

import android.os.SystemClock
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.lifecycle.ViewModelProvider
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AppInstrumentedTest {
    @get:Rule val rule = createAndroidComposeRule<MainActivity>()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val repository get() = Repository(context)
    private val controller get() = TimerController(context,repository)
    @Before fun reset() {
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        device.wakeUp()
        device.pressMenu()
        runBlocking { controller.cancel() }
        rule.waitUntil(60000) { rule.onAllNodesWithTag("main_scroll").fetchSemanticsNodes().isNotEmpty() }
        rule.activityRule.scenario.onActivity { ViewModelProvider(it)[ExposureViewModel::class.java].update { AppSettings() } }
        rule.waitForIdle()
    }
    private fun scroll(tag: String) { rule.onNodeWithTag("main_scroll").performScrollToNode(hasTestTag(tag)) }
    @Test fun exposureAndPersistenceAfterRecreation() {
        rule.onNodeWithTag("load_sample").performClick()
        scroll("exact_result")
        rule.onNodeWithTag("exact_result").assertTextEquals("32 秒")
        rule.activityRule.scenario.recreate()
        rule.waitUntil(30000) { rule.onAllNodesWithTag("main_scroll").fetchSemanticsNodes().isNotEmpty() }
        scroll("exact_result")
        rule.onNodeWithTag("exact_result").assertTextEquals("32 秒")
    }
    @Test fun starsNoticeDoesNotAlterIndependentExposure() {
        rule.onNodeWithTag("load_sample").performClick()
        rule.onNodeWithTag("tab_astro").performClick()
        rule.onNodeWithText("避免星星拖線：500 法則").assertExists()
        rule.onNodeWithTag("stars_dismiss").performClick()
        rule.onNodeWithTag("load_sample").performClick()
        scroll("exact_result")
        rule.onNodeWithTag("exact_result").assertTextEquals("32 秒")
        rule.onAllNodesWithTag("film_switch").assertCountEquals(0)
        rule.onNodeWithTag("tab_exposure").performClick()
        scroll("exact_result")
        rule.onNodeWithTag("exact_result").assertTextEquals("32 秒")
    }
    @Test fun filmResultAndTimerDialog() {
        rule.onNodeWithTag("load_sample").performClick()
        scroll("film_switch")
        rule.onNodeWithTag("film_switch").performClick()
        scroll("corrected_result")
        rule.onNodeWithTag("corrected_result").assertExists()
        scroll("open_timer")
        rule.onNodeWithTag("open_timer").performClick()
        rule.onNodeWithTag("timer_seconds").assertExists()
        rule.onNodeWithTag("timer_start").assertExists()
        rule.onNodeWithText("取消",useUnmergedTree=true).performClick()
    }
    @Test fun invalidReferenceShowsNoComputedResult() {
        rule.onNode(hasSetTextAction() and hasAnyAncestor(hasTestTag("ref_shutter"))).performTextInput("1/0")
        rule.onAllNodesWithTag("exact_result").assertCountEquals(0)
        scroll("input_message")
        rule.onNodeWithTag("input_message").assertExists()
    }
    @Test fun foregroundCountdownAndConsecutiveTimers() {
        repeat(2) {
            runBlocking { controller.start(1.0,false,false,false) }
            rule.waitUntil(30000) { runBlocking { repository.timer.first().status == "completed" } }
            runBlocking { controller.cancel() }
        }
    }
    @Test fun foregroundTimerExpiresWithCardOffscreen() {
        rule.onNodeWithTag("load_sample").performClick()
        runBlocking { controller.start(12.0, false, false, false) }
        rule.waitUntil(10000) { rule.onAllNodesWithTag("cancel_timer").fetchSemanticsNodes().isNotEmpty() }
        scroll("open_timer")
        rule.onNodeWithTag("open_timer").assertIsDisplayed()
        rule.waitUntil(30000) { runBlocking { repository.timer.first().status == "completed" } }
    }
    @Test fun cancelPreventsCompletion() {
        runBlocking { controller.start(1.0,true,false,false); controller.cancel() }
        Thread.sleep(2000)
        assertEquals("idle",runBlocking { repository.timer.first().status })
    }
    @Test fun lockedScreenAlarmCompletes() {
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        runBlocking { controller.start(12.0,true,false,false) }
        device.sleep()
        try {
            runBlocking { withTimeout(45000) { while(repository.timer.first().status != "completed") delay(500) } }
            assertEquals("completed",runBlocking { repository.timer.first().status })
        } finally { device.wakeUp(); device.pressMenu() }
    }
    @Test fun rebootStateAndStaleAlarmAreSafe() {
        runBlocking {
            controller.start(5.0,false,false,false)
            val t=repository.timer.first()
            controller.interruptedByBoot()
            controller.finish(t.id)
            assertEquals("interrupted",repository.timer.first().status)
            controller.cancel()
            controller.start(5.0,false,false,false)
            controller.finish(t.id)
            assertEquals("active",repository.timer.first().status)
            controller.cancel()
        }
    }
}
