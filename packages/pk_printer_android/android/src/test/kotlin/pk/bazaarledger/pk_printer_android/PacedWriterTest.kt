package pk.bazaarledger.pk_printer_android

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.OutputStream
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/**
 * The chunker, and the number the whole no-double-print design rests on.
 *
 * This package shipped with full JUnit scaffolding, mockito, verbose test
 * logging — and zero tests. Worse than zero: `useJUnitPlatform()` was
 * configured with no engine on the test runtime classpath, so the Gradle task
 * ran nothing and reported success. A green tick over an empty room.
 *
 * What is checked here is not "does it write bytes". It is the contract a
 * failed print reports back, because that is what decides whether a shopkeeper
 * gets one receipt or two.
 */
class PacedWriterTest {

    @Test
    fun `every byte arrives, in order, across chunk boundaries`() {
        // Longer than one chunk and not a multiple of it, so the last partial
        // chunk is genuinely exercised rather than skipped.
        val bytes = ByteArray(1000) { (it % 251).toByte() }
        val sink = ByteArrayOutputStream()

        val written = PacedWriter.write(sink, bytes, chunkSize = 256, chunkDelayMs = 0)

        assertEquals(bytes.size, written)
        assertContentEquals(bytes, sink.toByteArray())
    }

    @Test
    fun `it pauses between chunks and not after the last one`() {
        // A trailing sleep is not harmful, but it is a tell that the loop is
        // shaped wrongly, and the settle delay after the last byte is a
        // separate decision made by the caller.
        val bytes = ByteArray(1000)
        val pauses = mutableListOf<Long>()

        PacedWriter.write(
            ByteArrayOutputStream(),
            bytes,
            chunkSize = 250,
            chunkDelayMs = 20,
            sleep = pauses::add,
        )

        assertEquals(listOf(20L, 20L, 20L), pauses)
    }

    @Test
    fun `no pacing is asked for when the delay is zero`() {
        val pauses = mutableListOf<Long>()
        PacedWriter.write(
            ByteArrayOutputStream(),
            ByteArray(1000),
            chunkSize = 100,
            chunkDelayMs = 0,
            sleep = pauses::add,
        )
        assertTrue(pauses.isEmpty())
    }

    @Test
    fun `a link that dies mid-receipt reports how much paper moved`() {
        // The case this class exists for. 512 bytes are in the printer, the
        // cable is pulled, and the queue must be told a non-zero number so it
        // refuses to reprint on its own.
        val sink = FailingStream(failAfter = 512)

        val failure = assertFailsWith<PartialWrite> {
            PacedWriter.write(sink, ByteArray(1000), chunkSize = 256, chunkDelayMs = 0)
        }

        assertEquals(512, failure.bytesWritten)
    }

    @Test
    fun `a link that never opened reports zero, which is safe to retry`() {
        val sink = FailingStream(failAfter = 0)

        val failure = assertFailsWith<PartialWrite> {
            PacedWriter.write(sink, ByteArray(1000), chunkSize = 256, chunkDelayMs = 0)
        }

        assertEquals(
            0,
            failure.bytesWritten,
            "nothing came out, so the counter may offer to try again",
        )
    }

    @Test
    fun `a chunk counts only once it has been flushed`() {
        // write() succeeding is not evidence the printer took anything; the
        // bytes can sit in a buffer that never drains. Counting before the
        // flush would over-report, and over-reporting is the direction that
        // produces a second receipt.
        val sink = FlushFailingStream(failFlushAfter = 256)

        val failure = assertFailsWith<PartialWrite> {
            PacedWriter.write(sink, ByteArray(1000), chunkSize = 256, chunkDelayMs = 0)
        }

        assertEquals(256, failure.bytesWritten)
    }

    @Test
    fun `an empty receipt writes nothing and does not throw`() {
        assertEquals(
            0,
            PacedWriter.write(ByteArrayOutputStream(), ByteArray(0), 256, 0),
        )
    }

    @Test
    fun `a receipt shorter than one chunk goes out whole`() {
        val bytes = ByteArray(9) { it.toByte() }
        val sink = ByteArrayOutputStream()
        assertEquals(9, PacedWriter.write(sink, bytes, chunkSize = 256, chunkDelayMs = 0))
        assertContentEquals(bytes, sink.toByteArray())
    }

    @Test
    fun `a chunk size of zero is refused rather than looping forever`() {
        assertFailsWith<IllegalArgumentException> {
            PacedWriter.write(ByteArrayOutputStream(), ByteArray(10), 0, 0)
        }
    }
}

/** Takes [failAfter] bytes, then behaves like a pulled cable. */
private class FailingStream(private val failAfter: Int) : OutputStream() {
    private var taken = 0

    override fun write(b: Int) = throw IOException("not used")

    override fun write(b: ByteArray, off: Int, len: Int) {
        if (taken + len > failAfter) throw IOException("the link went away")
        taken += len
    }
}

/** Accepts every write, but stops flushing after [failFlushAfter] bytes. */
private class FlushFailingStream(private val failFlushAfter: Int) : OutputStream() {
    private var taken = 0

    override fun write(b: Int) = throw IOException("not used")

    override fun write(b: ByteArray, off: Int, len: Int) {
        taken += len
    }

    override fun flush() {
        if (taken > failFlushAfter) throw IOException("the buffer never drained")
    }
}
