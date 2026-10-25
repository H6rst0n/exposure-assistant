package tw.exposure.assistant

import org.junit.Assert.*
import org.junit.Test
import kotlin.math.*
import kotlin.random.Random

class ExposureMathTest {
    private val reference = Exposure(2.0,2.0,6400.0)
    @Test fun specifiedExposureAndNd() {
        assertEquals(32.0,ExposureMath.solve(reference,Exposure(2.0,1.0,400.0),Solve.SHUTTER,0.0),1e-10)
        assertEquals(256.0,ExposureMath.solve(reference,Exposure(2.0,1.0,400.0,3.0),Solve.SHUTTER,0.0),1e-10)
    }
    @Test fun compensationAndReferenceFilter() {
        assertEquals(64.0,ExposureMath.solve(reference,Exposure(2.0,1.0,400.0),Solve.SHUTTER,1.0),1e-10)
        assertEquals(16.0,ExposureMath.solve(reference,Exposure(2.0,1.0,400.0),Solve.SHUTTER,-1.0),1e-10)
        assertEquals(8.0,ExposureMath.solve(reference.copy(nd=2.0),Exposure(2.0,1.0,400.0),Solve.SHUTTER,0.0),1e-10)
    }
    @Test fun allSolversMatchExposureOverRandomCases() {
        val random = Random(371)
        repeat(200) {
            val r = Exposure(2.0.pow(random.nextDouble(0.0,5.0)),2.0.pow(random.nextDouble(-10.0,10.0)),2.0.pow(random.nextDouble(5.0,15.0)),random.nextDouble(0.0,10.0))
            val t = Exposure(2.0.pow(random.nextDouble(0.0,5.0)),2.0.pow(random.nextDouble(-10.0,10.0)),2.0.pow(random.nextDouble(5.0,15.0)),random.nextDouble(0.0,10.0))
            val c = random.nextDouble(-3.0,3.0)
            Solve.entries.forEach { what ->
                val result = ExposureMath.solve(r,t,what,c)
                val solved = when(what) { Solve.SHUTTER -> t.copy(seconds=result); Solve.APERTURE -> t.copy(aperture=result); Solve.ISO -> t.copy(iso=result); Solve.ND -> t.copy(nd=result) }
                assertEquals(ExposureMath.level(r)+c,ExposureMath.level(solved),1e-10)
            }
        }
    }
    @Test fun inverseValues() {
        val target = Exposure(4.0,128.0,400.0)
        assertEquals(400.0,ExposureMath.solve(reference,target,Solve.ISO,0.0),1e-10)
        assertEquals(4.0,ExposureMath.solve(reference,target,Solve.APERTURE,0.0),1e-10)
        assertEquals(0.0,ExposureMath.solve(reference,target,Solve.ND,0.0),1e-10)
    }
    @Test fun negativeNdIsPreservedForGuidance() {
        val nd=ExposureMath.solve(reference,Exposure(2.0,16.0,400.0),Solve.ND,0.0)
        assertEquals(-1.0,nd,1e-10)
        assertNull(ExposureMath.common(nd,Solve.ND))
    }
    @Test fun ndStackAndUnits() {
        assertEquals(9.0,ExposureMath.nd("3 + 6",NdUnit.STOPS),1e-10)
        assertEquals(9.0,ExposureMath.nd("8 + 64",NdUnit.FACTOR),1e-10)
        assertEquals(2.7/log10(2.0),ExposureMath.nd("0.9 + 1.8",NdUnit.DENSITY),1e-10)
        assertEquals(log2(1000.0),ExposureMath.nd("1000",NdUnit.FACTOR),1e-10)
        assertEquals(0.0,ExposureMath.nd("1",NdUnit.FACTOR),0.0)
    }
    @Test fun rejectsInvalidNd() {
        listOf("", "NaN", "Infinity", "3+", "-1", "101", "3+-2").forEach { value -> assertThrows(IllegalArgumentException::class.java) { ExposureMath.nd(value,NdUnit.STOPS) } }
        assertThrows(IllegalArgumentException::class.java) { ExposureMath.nd("0",NdUnit.FACTOR) }
    }
    @Test fun fractionInput() {
        assertEquals(0.008,ExposureMath.positive("1/125","快門"),1e-12)
        assertEquals(0.5,ExposureMath.positive(" 1 / 2 ","快門"),1e-12)
    }
    @Test fun rejectsInvalidInput() {
        listOf("", "0", "-1", "NaN", "Infinity", "1/0", "-1/-2", "1/2/3", "1e309").forEach { text -> assertThrows(IllegalArgumentException::class.java) { ExposureMath.positive(text,"數值") } }
        assertThrows(IllegalArgumentException::class.java) { ExposureMath.compensation("NaN") }
        assertThrows(IllegalArgumentException::class.java) { ExposureMath.compensation("101") }
    }
    @Test fun roundingDifferenceUsesCorrectSign() {
        assertEquals(1.0,ExposureMath.roundingStops(1.0,2.0,Solve.SHUTTER),1e-10)
        assertEquals(1.0,ExposureMath.roundingStops(100.0,200.0,Solve.ISO),1e-10)
        assertEquals(-2.0,ExposureMath.roundingStops(2.0,4.0,Solve.APERTURE),1e-10)
        assertEquals(-1.0,ExposureMath.roundingStops(3.0,4.0,Solve.ND),1e-10)
        assertEquals(1.0/125,ExposureMath.common(1.0/127,Solve.SHUTTER)!!,1e-10)
    }
    @Test fun filmKnownExampleAndBoundary() {
        val hp5=Films.find("hp5")!!
        assertEquals(20.417379,Films.corrected(10.0,hp5),1e-5)
        assertEquals(1.0,Films.corrected(1.0,hp5),0.0)
        assertEquals(0.5,Films.corrected(0.5,hp5),0.0)
        assertTrue(Films.corrected(1.001,hp5)>1.001)
    }
    @Test fun manufacturerCoefficients() {
        assertEquals(listOf(1.43,1.33,1.26,1.41,1.33,1.26,1.31,1.31,1.25,1.26,1.30),Films.all.map { it.exponent })
        assertNull(Films.find("unknown"))
    }
    @Test fun filmAppliedAfterNdExactlyOnce() {
        val form=FormState(Inputs("2","10","400"),Inputs("2","","400","3"),filmMode=true)
        val calc=calculate(form,false)
        assertEquals(80.0,calc.exact,1e-8)
        assertEquals(80.0.pow(1.31),calc.corrected!!,1e-8)
    }
    @Test fun unknownFilmDoesNotInventCorrection() {
        val form=FormState(Inputs("2","10","400"),Inputs("2","","400"),filmMode=true,filmId="unknown")
        assertNull(calculate(form,false).corrected)
    }
    @Test fun filmInverseAndStarsNeverApplyCorrection() {
        val form=FormState(Inputs("2","10","400"),Inputs("2","10","400"),solve=Solve.APERTURE,filmMode=true)
        assertNull(calculate(form,false).corrected)
        assertNull(calculate(form.copy(solve=Solve.SHUTTER),true).corrected)
    }
    @Test fun missingReferenceStopsCalculation() {
        assertThrows(IllegalArgumentException::class.java) { calculate(FormState(),true) }
    }
    @Test fun solvedFieldIsNotRequired() {
        val form=FormState(Inputs("2","2","6400"),Inputs("2","invalid","400"))
        assertEquals(32.0,calculate(form,false).exact,1e-10)
    }
    @Test fun starsIgnoreHiddenNdSettings() {
        val form=FormState(Inputs("2","2","6400","bad"),Inputs("2","","400","bad"))
        assertEquals(32.0,calculate(form,true).exact,1e-10)
        assertTrue(STAR_NOTICE.contains("500 ÷ 全片幅等效焦距"))
        assertTrue(STAR_NOTICE.contains("6.7 秒"))
    }
    @Test fun formattingLongTimeAndFractions() {
        assertEquals("01:01:01",durationLabel(3661))
        assertEquals("1/125 秒",secondsLabel(1.0/125))
        assertEquals("32 秒",secondsLabel(32.0))
    }
}
