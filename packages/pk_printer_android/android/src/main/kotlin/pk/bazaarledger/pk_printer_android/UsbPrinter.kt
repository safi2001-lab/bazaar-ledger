package pk.bazaarledger.pk_printer_android

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import androidx.core.content.ContextCompat
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * The printer already cabled to the counter.
 *
 * This is the shape most Pakistani shop counters actually have: an 80mm
 * thermal printer on a USB lead, bought for six to twelve thousand rupees. The
 * battery Bluetooth unit is what a delivery man carries, and the LAN one is
 * how a counter and a back office share a machine — but the cabled one is the
 * default, and a product that cannot drive it asks a shopkeeper to buy a
 * second printer to use it.
 *
 * ## It is a printer, not a serial port
 *
 * These devices enumerate as USB **printer class (0x07)**, not as CDC-ACM
 * serial. Every "usb_serial" package on pub.dev looks for 0x02/0x0A and finds
 * nothing, which is why they all report no device attached against a printer
 * that is plainly plugged in and powered.
 *
 * ## The Android 14 permission landmine
 *
 * At targetSdk 34+ the system refuses a PendingIntent that is BOTH
 * `FLAG_MUTABLE` and carries an implicit Intent. The obvious fix — switch to
 * `FLAG_IMMUTABLE` — stops the crash and silently breaks printing, because
 * `UsbManager` fills the grant result INTO the intent and an immutable one has
 * nowhere to put it. So the permission dialog appears, the shopkeeper taps
 * Allow, and nothing happens, forever.
 *
 * The combination that works is an EXPLICIT intent (`setPackage`) plus
 * `FLAG_MUTABLE`: explicit satisfies the restriction, mutable lets the system
 * write the answer back. `registerReceiver` also requires an export flag at
 * targetSdk 34+ or it throws SecurityException, which is a separate change
 * that lands at the same version and is just as fatal.
 */
class UsbPrinter(private val context: Context) {

    private val manager: UsbManager?
        get() = context.getSystemService(Context.USB_SERVICE) as? UsbManager

    fun isAvailable(): Boolean =
        context.packageManager.hasSystemFeature("android.hardware.usb.host") &&
            manager != null

    /**
     * Printers currently plugged in.
     *
     * Filtered on interface class 0x07 rather than on vendor id. A vendor list
     * is a list of the printers somebody remembered, and the machines this
     * product exists for are unbranded units from a dozen importers.
     */
    fun devices(): List<Map<String, Any?>> {
        val manager = manager ?: return emptyList()
        return manager.deviceList.values
            .filter { printerInterfaceOf(it) != null }
            .map { device ->
                mapOf(
                    "address" to device.deviceName,
                    "name" to (device.productName ?: device.deviceName),
                    "vendorId" to device.vendorId,
                    "productId" to device.productId,
                    "hasPermission" to (manager.hasPermission(device)),
                )
            }
    }

    /**
     * Sends [bytes] to the device named [address], waiting for permission if
     * the shopkeeper has not granted it yet.
     *
     * Returns how many bytes the printer took. Throws [PartialWrite] carrying
     * that count when it stops part way.
     */
    fun send(
        address: String,
        bytes: ByteArray,
        chunkDelayMs: Int,
        timeoutMs: Int = DEFAULT_TIMEOUT_MS,
    ): Int {
        val manager = manager ?: throw IOException("This device has no USB host support.")
        val device = manager.deviceList[address]
            ?: throw IOException("No printer at $address. Is the cable in?")

        if (!manager.hasPermission(device)) {
            requestPermission(manager, device)
            if (!manager.hasPermission(device)) {
                throw IOException("Permission to use the printer was not granted.")
            }
        }

        val iface = printerInterfaceOf(device)
            ?: throw IOException("That USB device is not a printer.")
        val endpoint = bulkOutOf(iface)
            ?: throw IOException("The printer has no endpoint to send to.")

        val connection: UsbDeviceConnection = manager.openDevice(device)
            ?: throw IOException("Could not open the printer.")

        try {
            // `true` forces the kernel to hand the interface over. Android's
            // own usblp driver claims printers on some builds, and without the
            // force this fails on exactly those devices.
            if (!connection.claimInterface(iface, true)) {
                throw IOException("Another program is using the printer.")
            }
            return UsbBulkWriter.write(
                bytes = bytes,
                maxPacket = endpoint.maxPacketSize,
                timeoutMs = timeoutMs,
                chunkDelayMs = chunkDelayMs,
            ) { buffer, offset, length, timeout ->
                // The three-argument overload cannot start at an offset, so the
                // chunk is copied out. A receipt is a few kilobytes; the copy
                // costs nothing and the alternative is a UsbRequest queue whose
                // failure modes are far harder to reason about.
                val chunk = buffer.copyOfRange(offset, offset + length)
                connection.bulkTransfer(endpoint, chunk, chunk.size, timeout)
            }
        } finally {
            runCatching { connection.releaseInterface(iface) }
            runCatching { connection.close() }
        }
    }

    /**
     * Asks once, and waits.
     *
     * Synchronous because it is called from the plugin's IO executor, never
     * from the main thread — the dialog is drawn by the system, so nothing here
     * needs to be on the UI thread, and a callback would leave the caller with
     * no way to report the outcome back through the method channel.
     */
    private fun requestPermission(manager: UsbManager, device: UsbDevice) {
        val latch = CountDownLatch(1)
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action == ACTION_USB_PERMISSION) latch.countDown()
            }
        }

        // RECEIVER_NOT_EXPORTED is mandatory at targetSdk 34+; without it
        // registerReceiver throws SecurityException. ContextCompat handles the
        // older versions, which is why it is used rather than the raw call.
        ContextCompat.registerReceiver(
            context,
            receiver,
            IntentFilter(ACTION_USB_PERMISSION),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )

        try {
            // EXPLICIT (setPackage) so FLAG_MUTABLE is legal at targetSdk 34+,
            // and MUTABLE so UsbManager can write the grant result into it.
            // Neither half works without the other: implicit + mutable throws,
            // and explicit + immutable leaves the shopkeeper tapping Allow
            // against a dialog whose answer goes nowhere.
            val intent = Intent(ACTION_USB_PERMISSION).setPackage(context.packageName)
            val pending = PendingIntent.getBroadcast(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
            )
            manager.requestPermission(device, pending)
            latch.await(PERMISSION_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        } finally {
            runCatching { context.unregisterReceiver(receiver) }
        }
    }

    private fun printerInterfaceOf(device: UsbDevice): UsbInterface? {
        for (i in 0 until device.interfaceCount) {
            val iface = device.getInterface(i)
            if (iface.interfaceClass == UsbConstants.USB_CLASS_PRINTER) return iface
        }
        return null
    }

    private fun bulkOutOf(iface: UsbInterface): UsbEndpoint? {
        for (i in 0 until iface.endpointCount) {
            val endpoint = iface.getEndpoint(i)
            if (endpoint.type == UsbConstants.USB_ENDPOINT_XFER_BULK &&
                endpoint.direction == UsbConstants.USB_DIR_OUT
            ) {
                return endpoint
            }
        }
        return null
    }

    private companion object {
        const val ACTION_USB_PERMISSION = "pk.bazaarledger.USB_PERMISSION"
        const val DEFAULT_TIMEOUT_MS = 5_000
        const val PERMISSION_TIMEOUT_SECONDS = 60L
    }
}
