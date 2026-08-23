package pk.bazaarledger.pk_printer_android

import java.io.IOException

/**
 * Pushes bytes down a USB bulk endpoint, and counts what actually arrived.
 *
 * Separate from the plugin so it can be tested without a printer plugged in.
 * `UsbDeviceConnection.bulkTransfer` is a final method on a framework class,
 * which cannot be mocked without Robolectric, so the transfer itself arrives
 * here as a function.
 *
 * The counting is the point, exactly as it is for Bluetooth: the number of
 * bytes the printer took is what decides whether a failed job may be sent
 * again on its own. A thermal printer has no memory and no job identity, so a
 * retry after paper has already moved hands the customer two half-receipts.
 */
object UsbBulkWriter {

    /**
     * Moves one chunk and returns how many bytes went, or a negative number on
     * failure. Mirrors `UsbDeviceConnection.bulkTransfer`.
     */
    fun interface Transfer {
        fun send(buffer: ByteArray, offset: Int, length: Int, timeoutMs: Int): Int
    }

    /**
     * Writes [bytes] in chunks of at most [maxPacket], returning the total sent.
     *
     * Two things here are easy to get wrong and both produce a receipt that is
     * subtly, intermittently incomplete rather than an error anybody sees.
     *
     * `bulkTransfer` returns the count it ACTUALLY moved, and it is routinely
     * less than what it was asked for — the endpoint has a packet size and a
     * queue, and a busy printer takes what it can. Treating any non-negative
     * return as "the whole chunk went" silently drops the remainder. The tail
     * of a receipt is the cut command, so the symptom is a bill that prints
     * perfectly and never cuts, on some printers, some of the time.
     *
     * And a return of zero is not progress. Without a bound on consecutive
     * zero-length transfers a stalled endpoint spins here forever, holding the
     * UI thread's work queue behind it, which reads as the app freezing rather
     * than as a printer problem.
     */
    fun write(
        bytes: ByteArray,
        maxPacket: Int,
        timeoutMs: Int,
        chunkDelayMs: Int = 0,
        sleep: (Long) -> Unit = { Thread.sleep(it) },
        transfer: Transfer,
    ): Int {
        require(maxPacket > 0) { "maxPacket must be positive, was $maxPacket" }

        var written = 0
        var stalls = 0

        while (written < bytes.size) {
            val want = minOf(maxPacket, bytes.size - written)
            val moved = transfer.send(bytes, written, want, timeoutMs)

            if (moved < 0) {
                throw PartialWrite(written, IOException("the printer stopped taking data"))
            }
            if (moved == 0) {
                // Nothing moved. Give it a few tries, then stop rather than
                // spin: a printer that is out of paper or jammed reports this
                // and never recovers on its own.
                if (++stalls >= MAX_STALLS) {
                    throw PartialWrite(
                        written,
                        IOException("the printer stopped accepting data after $written bytes"),
                    )
                }
                sleep(STALL_BACKOFF_MS)
                continue
            }

            stalls = 0
            written += moved

            // Paced for the same reason as Bluetooth: the controller behind the
            // endpoint drains slower than USB delivers, and an overflow is not
            // reported -- the receipt just comes out garbled, and only the long
            // ones.
            if (chunkDelayMs > 0 && written < bytes.size) {
                sleep(chunkDelayMs.toLong())
            }
        }
        return written
    }

    /** Consecutive zero-byte transfers before giving up. */
    private const val MAX_STALLS = 20

    private const val STALL_BACKOFF_MS = 25L
}
