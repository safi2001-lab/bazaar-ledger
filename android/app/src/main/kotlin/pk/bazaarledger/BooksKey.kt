package pk.bazaarledger

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * The key the books are encrypted with: 32 random bytes made once on this
 * phone, kept on disk sealed by an AES key that lives in the Android Keystore
 * and never leaves it.
 *
 * Kept in `no_backup`, beside the books, so neither Auto Backup nor a
 * device-to-device transfer carries it to another phone. A key sealed by
 * another phone's keystore is useless there anyway; a shop moves phones with
 * a backup, which carries the books in its own passphrase-sealed envelope.
 */
internal class BooksKey(private val dir: File) {
    private val file = File(dir, "books.key")

    fun hex(): String {
        val wrapping = wrappingKey()
        if (file.exists()) {
            // Never replaced once written. If the keystore lost its key, this
            // throws, and the books say they are locked rather than a new key
            // being minted over the only way back into them.
            val sealed = file.readBytes()
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(
                Cipher.DECRYPT_MODE,
                wrapping,
                GCMParameterSpec(TAG_BITS, sealed, 0, IV_BYTES),
            )
            return toHex(cipher.doFinal(sealed, IV_BYTES, sealed.size - IV_BYTES))
        }
        val key = ByteArray(KEY_BYTES).also { SecureRandom().nextBytes(it) }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, wrapping)
        val sealed = cipher.iv + cipher.doFinal(key)
        dir.mkdirs()
        val partial = File(dir, "books.key.partial")
        partial.writeBytes(sealed)
        if (!partial.renameTo(file)) {
            throw IllegalStateException("could not keep the books key")
        }
        return toHex(key)
    }

    private fun wrappingKey(): SecretKey {
        val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private companion object {
        const val KEYSTORE = "AndroidKeyStore"
        const val ALIAS = "bazaar_ledger_books"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val TAG_BITS = 128
        const val IV_BYTES = 12
        const val KEY_BYTES = 32

        fun toHex(bytes: ByteArray): String =
            bytes.joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }
}
