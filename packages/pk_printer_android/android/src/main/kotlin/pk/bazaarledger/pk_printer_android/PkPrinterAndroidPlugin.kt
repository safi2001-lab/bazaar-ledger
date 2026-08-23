package pk.bazaarledger.pk_printer_android

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Bluetooth Serial Port Profile, for the battery printer a delivery man carries.
 *
 * Written here rather than taken from pub.dev, for three reasons that are all
 * about this project rather than about pride. AGP 9 refuses any plugin that
 * applies `kotlin-android`, which is most of the Bluetooth ecosystem. The one
 * package confirmed to build against AGP 9 is GPL-3.0, which a Play Store app
 * cannot take. And several of the alternatives declare ACCESS_FINE_LOCATION in
 * their own manifests, which the merger would pull into this app whether it is
 * used or not — dragging a billing app into Play's Location policy to find a
 * printer.
 *
 * What is here is deliberately small: no discovery loop, no GATT, no service
 * browsing. A shopkeeper pairs the printer once in Android's own settings and
 * this only ever enumerates what is already bonded. That is the smallest
 * permission surface there is — BLUETOOTH_CONNECT alone, no BLUETOOTH_SCAN, no
 * location, ever.
 */
class PkPrinterAndroidPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    /** All printer I/O, off the main thread and one job at a time. */
    private val io = Executors.newSingleThreadExecutor()

    private val usb: UsbPrinter by lazy { UsbPrinter(context) }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        io.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(adapter()?.isEnabled == true && hasConnectPermission())
            "hasPermission" -> result.success(hasConnectPermission())
            "bondedPrinters" -> bondedPrinters(result)
            "send" -> send(call, result)

            // The cabled printer. Same channel, separate methods: the two
            // transports share nothing but a wire format, and a single `send`
            // switching on a string would make the bytes-written contract --
            // the thing the whole no-double-print design rests on -- depend on
            // which branch a caller happened to take.
            "usbIsAvailable" -> result.success(usb.isAvailable())
            "usbDevices" -> result.success(usb.devices())
            "usbSend" -> usbSend(call, result)

            else -> result.notImplemented()
        }
    }

    private fun usbSend(call: MethodCall, result: MethodChannel.Result) {
        val address = call.argument<String>("address")
        val bytes = call.argument<ByteArray>("bytes")
        val chunkDelayMs = call.argument<Int>("chunkDelayMs") ?: 0
        val settleMs = call.argument<Int>("settleMs") ?: 0

        if (address == null || bytes == null) {
            result.error("args", "address and bytes are required.", null)
            return
        }

        io.execute {
            try {
                usb.send(address, bytes, chunkDelayMs)
                // Held open briefly for the same reason as Bluetooth: closing
                // straight after the last byte truncates the tail, and the tail
                // is the cut command.
                if (settleMs > 0) Thread.sleep(settleMs.toLong())
                result.success(null)
            } catch (partial: PartialWrite) {
                result.error("send", partial.message ?: partial.toString(), partial.bytesWritten)
            } catch (error: Throwable) {
                // Nothing told us paper did not move, so it is reported as
                // though it did and a person decides. `null` details rather
                // than 0: absent is not zero, and zero means "safe to retry".
                result.error("send", error.message ?: error.toString(), null)
            }
        }
    }

    private fun adapter(): BluetoothAdapter? =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    /**
     * BLUETOOTH_CONNECT, and only on the versions that have it.
     *
     * Below Android 12 the old BLUETOOTH permission is install-time and always
     * granted, so asking would return false for a device that is perfectly able
     * to print.
     */
    private fun hasConnectPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.BLUETOOTH_CONNECT,
        ) == PackageManager.PERMISSION_GRANTED
    }

    @SuppressLint("MissingPermission")
    private fun bondedPrinters(result: MethodChannel.Result) {
        if (!hasConnectPermission()) {
            result.error("permission", "Bluetooth permission has not been granted.", null)
            return
        }
        val adapter = adapter()
        if (adapter == null || !adapter.isEnabled) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }
        // Everything paired, not everything that looks like a printer. The
        // Bluetooth class of a cheap thermal printer is frequently reported as
        // UNCATEGORIZED or as an audio device, so filtering by class hides the
        // very machines this exists for. The shopkeeper picks theirs by name.
        result.success(
            adapter.bondedDevices.map { device ->
                mapOf(
                    "address" to device.address,
                    "name" to (device.name ?: device.address),
                    "deviceClass" to device.bluetoothClass?.deviceClass,
                )
            },
        )
    }

    private fun send(call: MethodCall, result: MethodChannel.Result) {
        val address = call.argument<String>("address")
        val bytes = call.argument<ByteArray>("bytes")
        val chunkSize = call.argument<Int>("chunkSize") ?: 256
        val chunkDelayMs = call.argument<Int>("chunkDelayMs") ?: 20
        val settleMs = call.argument<Int>("settleMs") ?: 400

        if (address == null || bytes == null) {
            result.error("args", "address and bytes are required.", null)
            return
        }
        if (!hasConnectPermission()) {
            result.error("permission", "Bluetooth permission has not been granted.", 0)
            return
        }

        io.execute {
            var written = 0
            var socket: BluetoothSocket? = null
            try {
                val adapter = adapter()
                    ?: throw IOException("This device has no Bluetooth radio.")
                if (!adapter.isEnabled) throw IOException("Bluetooth is switched off.")

                // Discovery is bandwidth-hungry and will make a connection
                // attempt fail or crawl. Nothing here starts it, but another
                // app might have.
                @SuppressLint("MissingPermission")
                if (adapter.isDiscovering) adapter.cancelDiscovery()

                val device = adapter.getRemoteDevice(address)
                socket = connect(device)

                // The chunking, the pacing and the bytes-written contract all
                // live in PacedWriter, where they can be tested without a
                // printer in the room. They used to be inline here, which is
                // why they never were.
                written = PacedWriter.write(
                    socket.outputStream,
                    bytes,
                    chunkSize,
                    chunkDelayMs,
                )

                // Closing straight after the last write truncates the tail, and
                // the tail is the cut command — so the symptom is a receipt
                // that prints perfectly and never cuts.
                Thread.sleep(settleMs.toLong())
                result.success(null)
            } catch (partial: PartialWrite) {
                written = partial.bytesWritten
                result.error("send", partial.message ?: partial.toString(), written)
            } catch (error: Throwable) {
                // `written` travels with the error because it decides whether a
                // retry is allowed. Nothing written means nothing came out and
                // the job can go again; anything else means paper has already
                // moved and only a person may decide.
                result.error("send", error.message ?: error.toString(), written)
            } finally {
                try {
                    socket?.close()
                } catch (_: IOException) {
                    // The link is already gone, which is what brought us here.
                }
            }
        }
    }

    /**
     * Three ways in, because cheap printers publish broken service records.
     *
     * The documented call is the first one. Many of the modules this ships
     * against report an empty or malformed SDP record, so the secure lookup
     * finds nothing and the printer appears unreachable even though it is
     * paired and switched on. The insecure variant skips the pairing check,
     * and the reflection call skips service discovery entirely and goes
     * straight at RFCOMM channel 1, which is where these modules always listen.
     */
    @SuppressLint("MissingPermission")
    private fun connect(device: BluetoothDevice): BluetoothSocket {
        val attempts: List<() -> BluetoothSocket> = listOf(
            { device.createRfcommSocketToServiceRecord(SPP_UUID) },
            { device.createInsecureRfcommSocketToServiceRecord(SPP_UUID) },
            {
                val method = device.javaClass.getMethod(
                    "createRfcommSocket",
                    Int::class.javaPrimitiveType,
                )
                method.invoke(device, 1) as BluetoothSocket
            },
        )

        var last: Throwable? = null
        for (attempt in attempts) {
            try {
                val socket = attempt()
                socket.connect()
                return socket
            } catch (error: Throwable) {
                last = error
            }
        }
        throw IOException(
            "Could not open a connection to ${device.address}: ${last?.message}",
        )
    }

    private companion object {
        const val CHANNEL = "pk.bazaarledger/printer"

        /** The Serial Port Profile. Every ESC/POS printer speaks it. */
        val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805f9b34fb")
    }
}
