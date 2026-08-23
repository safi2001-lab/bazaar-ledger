package pk.bazaarledger.pk_printer_android

import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/**
 * Pushing bytes down a USB bulk endpoint.
 *
 * `bulkTransfer` returns the count it ACTUALLY moved, and that count is
 * routinely less than what it was asked for. Treating any non-negative return
 * as "the whole chunk went" silently drops the remainder — and the remainder
 * at the end of a receipt is the cut command, so the symptom is a bill that
 * prints perfectly and never cuts, on some printers, some of the time.
 *
 * These tests exist because that failure is invisible at a bench and obvious
 * at a counter.
 */
class UsbBulkWriterTest {

    @Test
    fun `every byte arrives, in order, when the endpoint takes full packets`() {
        val bytes = ByteArray(1000) { (it % 251).toByte() }
        val sink = mutableListOf<Byte>()

        val written = UsbBulkWriter.write(bytes, maxPacket = 64, timeoutMs = 100) {
            buffer, offset, length, _ ->
            sink.addAll(buffer.copyOfRange(offset, offset + length).toList())
            length
        }

        assertEquals(1000, written)
        assertContentEquals(bytes, sink.toByteArray())
    }

    @Test
    fun `a short transfer is resumed, not treated as a whole chunk`() {
        // The defect this class exists for. The endpoint takes 10 bytes of the
        // 64 it was offered; a writer that trusted the request size would jump
        // 64 forward and lose 54 bytes out of the middle of the receipt.
        val bytes = ByteArray(200) { (it % 251).toByte() }
        val sink = mutableListOf<Byte>()

        val written = UsbBulkWriter.write(bytes, maxPacket = 64, timeoutMs = 100) {
            buffer, offset, length, _ ->
            val moved = minOf(10, length)
            sink.addAll(buffer.copyOfRange(offset, offset + moved).toList())
            moved
        }

        assertEquals(200, written)
        assertContentEquals(
            bytes,
            sink.toByteArray(),
            "bytes were skipped when the endpoint took less than it was offered",
        )
    }

    @Test
    fun `a negative return reports how much had already gone`() {
        // Paper has moved. The queue must be told a non-zero number so it
        // refuses to reprint on its own.
        val failure = assertFailsWith<PartialWrite> {
            UsbBulkWriter.write(ByteArray(500), maxPacket = 64, timeoutMs = 100) {
                _, offset, length, _ ->
                if (offset >= 256) -1 else length
            }
        }
        assertEquals(256, failure.bytesWritten)
    }

    @Test
    fun `a failure on the very first packet reports zero, which is retryable`() {
        val failure = assertFailsWith<PartialWrite> {
            UsbBulkWriter.write(ByteArray(500), maxPacket = 64, timeoutMs = 100) {
                _, _, _, _ ->
                -1
            }
        }
        assertEquals(0, failure.bytesWritten, "nothing came out, so a retry is safe")
    }

    @Test
    fun `a stalled endpoint gives up instead of spinning forever`() {
        // A printer out of paper or jammed returns zero and never recovers.
        // Without a bound this loops forever holding the IO thread, which
        // reads as the app freezing rather than as a printer problem.
        var attempts = 0
        val failure = assertFailsWith<PartialWrite> {
            UsbBulkWriter.write(
                ByteArray(500),
                maxPacket = 64,
                timeoutMs = 100,
                sleep = {},
            ) { _, _, _, _ ->
                attempts++
                0
            }
        }
        assertEquals(0, failure.bytesWritten)
        assertTrue(attempts in 1..50, "gave up after $attempts attempts")
    }

    @Test
    fun `progress resets the stall count`() {
        // An endpoint that pauses occasionally is normal. Only CONSECUTIVE
        // zero-length transfers mean it has stopped.
        var call = 0
        val written = UsbBulkWriter.write(
            ByteArray(300),
            maxPacket = 64,
            timeoutMs = 100,
            sleep = {},
        ) { _, _, length, _ ->
            // Two stalls, then progress, over and over.
            if (call++ % 3 != 2) 0 else length
        }
        assertEquals(300, written)
    }

    @Test
    fun `it paces between packets and not after the last one`() {
        val pauses = mutableListOf<Long>()
        UsbBulkWriter.write(
            ByteArray(256),
            maxPacket = 64,
            timeoutMs = 100,
            chunkDelayMs = 5,
            sleep = pauses::add,
        ) { _, _, length, _ -> length }

        assertEquals(listOf(5L, 5L, 5L), pauses)
    }

    @Test
    fun `an empty receipt writes nothing and does not throw`() {
        val written = UsbBulkWriter.write(ByteArray(0), maxPacket = 64, timeoutMs = 100) {
            _, _, _, _ ->
            0
        }
        assertEquals(0, written)
    }

    @Test
    fun `a packet size of zero is refused rather than looping forever`() {
        assertFailsWith<IllegalArgumentException> {
            UsbBulkWriter.write(ByteArray(10), maxPacket = 0, timeoutMs = 100) {
                _, _, length, _ ->
                length
            }
        }
    }

    @Test
    fun `the timeout is handed to every transfer`() {
        val seen = mutableSetOf<Int>()
        UsbBulkWriter.write(ByteArray(200), maxPacket = 64, timeoutMs = 1234) {
            _, _, length, timeout ->
            seen.add(timeout)
            length
        }
        assertEquals(setOf(1234), seen)
    }
}
