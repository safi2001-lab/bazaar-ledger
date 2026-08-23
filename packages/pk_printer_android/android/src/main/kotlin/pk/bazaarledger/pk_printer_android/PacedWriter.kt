package pk.bazaarledger.pk_printer_android

import java.io.IOException
import java.io.OutputStream

/**
 * How many bytes the printer took before something went wrong.
 *
 * This number is the whole reason the class exists. A thermal printer has no
 * memory and no job identity: asked twice, it prints twice. So the only thing
 * that can decide whether a failed job may be retried automatically is whether
 * any paper moved — zero means nothing came out and the counter may try again,
 * anything else means a person has to look at the paper and decide.
 *
 * Losing the count turns every failure into "safe to retry", which is how a
 * flaky link hands the customer two of every long bill.
 */
class PartialWrite(
    val bytesWritten: Int,
    override val cause: Throwable,
) : IOException(cause.message ?: cause.toString())

/**
 * Writes bytes to a printer in paced chunks.
 *
 * Extracted from the Bluetooth send path so it can be tested at all. It was
 * inline in a method that also opened an RFCOMM socket, which meant the
 * chunking, the pacing and the bytes-written contract could only be exercised
 * with a real printer in the room — so they never were.
 *
 * Shared by every transport, because the reason for pacing is the same in all
 * of them: the module between the link and the print head feeds the controller
 * over an internal UART with no flow control, so bytes arrive faster than the
 * printer drains. Nothing reports an error when it overflows. The receipt
 * simply comes out garbled, and only the long ones — which is exactly why it
 * survives testing and fails in the shop.
 */
object PacedWriter {

    /**
     * Pushes [bytes] through [out], and returns how many arrived.
     *
     * [sleep] is a parameter so a test does not spend real seconds proving the
     * pacing happened, and so the delays can be asserted rather than assumed.
     */
    fun write(
        out: OutputStream,
        bytes: ByteArray,
        chunkSize: Int,
        chunkDelayMs: Int,
        sleep: (Long) -> Unit = { Thread.sleep(it) },
    ): Int {
        require(chunkSize > 0) { "chunkSize must be positive, was $chunkSize" }

        var written = 0
        try {
            while (written < bytes.size) {
                val end = minOf(written + chunkSize, bytes.size)
                out.write(bytes, written, end - written)
                out.flush()
                written = end
                if (chunkDelayMs > 0 && written < bytes.size) {
                    sleep(chunkDelayMs.toLong())
                }
            }
            out.flush()
        } catch (error: Throwable) {
            // `written` counts only chunks that were written AND flushed, so it
            // never over-reports. Under-reporting is the safe direction: it
            // makes a job look like it printed more than it did, which stops a
            // retry, and a missing receipt is a smaller problem than a
            // duplicated one.
            throw PartialWrite(written, error)
        }
        return written
    }
}
