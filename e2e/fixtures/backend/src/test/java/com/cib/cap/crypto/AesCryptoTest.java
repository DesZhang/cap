package com.cib.cap.crypto;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

/**
 * AesCrypto 和 SecretResolver 单元测试
 */
class AesCryptoTest {

    private static final String TEST_KEY = "test-encryption-key-12345";

    @Test
    void encryptThenDecrypt_returnsOriginalPlaintext() {
        String plaintext = "my-cap-secret-key";
        String encrypted = AesCrypto.encrypt(plaintext, TEST_KEY);
        String decrypted = AesCrypto.decrypt(encrypted, TEST_KEY);

        assertEquals(plaintext, decrypted);
    }

    @Test
    void encryptProducesDifferentCiphertextEachTime() {
        String plaintext = "same-input";
        String encrypted1 = AesCrypto.encrypt(plaintext, TEST_KEY);
        String encrypted2 = AesCrypto.encrypt(plaintext, TEST_KEY);

        // 随机 IV 保证每次加密结果不同
        assertNotEquals(encrypted1, encrypted2);
    }

    @Test
    void decryptWithWrongKey_throwsException() {
        String encrypted = AesCrypto.encrypt("secret", TEST_KEY);

        assertThrows(RuntimeException.class, () -> AesCrypto.decrypt(encrypted, "wrong-key"));
    }

    @Test
    void decryptGarbageInput_throwsException() {
        assertThrows(RuntimeException.class, () -> AesCrypto.decrypt("not-valid-base64!!!", TEST_KEY));
    }

    @Test
    void resolve_plainTextValue_returnsAsIs() {
        assertEquals("my-plain-secret", SecretResolver.resolve("my-plain-secret", null));
    }

    @Test
    void resolve_plainTextValue_withKey_returnsAsIs() {
        assertEquals("my-plain-secret", SecretResolver.resolve("my-plain-secret", TEST_KEY));
    }

    @Test
    void resolve_encryptedValue_withKey_decrypts() {
        String plaintext = "my-secret-to-encrypt";
        String encrypted = AesCrypto.encrypt(plaintext, TEST_KEY);
        String wrapped = "ENC(" + encrypted + ")";

        String resolved = SecretResolver.resolve(wrapped, TEST_KEY);
        assertEquals(plaintext, resolved);
    }

    @Test
    void resolve_encryptedValue_withoutKey_throwsException() {
        String encrypted = AesCrypto.encrypt("secret", TEST_KEY);
        String wrapped = "ENC(" + encrypted + ")";

        assertThrows(IllegalStateException.class, () -> SecretResolver.resolve(wrapped, null));
    }
}
