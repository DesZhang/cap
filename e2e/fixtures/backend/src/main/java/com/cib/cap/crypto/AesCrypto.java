package com.cib.cap.crypto;

import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.Base64;

/**
 * AES-256-GCM 加解密工具
 * <p>
 * 用于加密 application.properties 中的敏感配置（如 Cap Secret Key）。
 * 加密密钥通过环境变量 CAP_ENCRYPTION_KEY 提供。
 * <p>
 * 加密格式: Base64(12字节IV + 密文 + GCM标签)，输出为单一 Base64 字符串。
 */
public class AesCrypto {

    private static final String ALGORITHM = "AES/GCM/NoPadding";
    private static final int IV_LENGTH = 12;
    private static final int TAG_LENGTH = 128;

    /**
     * 从环境变量获取加密密钥，生成 AES-256 密钥规格。
     * 密钥字符串通过 SHA-256 哈希扩展到 32 字节。
     */
    static SecretKeySpec deriveKey(String encryptionKey) {
        try {
            byte[] keyBytes = java.security.MessageDigest.getInstance("SHA-256")
                    .digest(encryptionKey.getBytes(StandardCharsets.UTF_8));
            return new SecretKeySpec(keyBytes, "AES");
        } catch (Exception e) {
            throw new RuntimeException("生成加密密钥失败: " + e.getMessage(), e);
        }
    }

    /**
     * 加密明文，返回 Base64 编码的密文（包含 IV）。
     */
    public static String encrypt(String plaintext, String encryptionKey) {
        try {
            SecretKeySpec key = deriveKey(encryptionKey);
            byte[] iv = new byte[IV_LENGTH];
            new SecureRandom().nextBytes(iv);

            Cipher cipher = Cipher.getInstance(ALGORITHM);
            cipher.init(Cipher.ENCRYPT_MODE, key, new GCMParameterSpec(TAG_LENGTH, iv));

            byte[] ciphertext = cipher.doFinal(plaintext.getBytes(StandardCharsets.UTF_8));

            // 拼接 IV + 密文
            byte[] combined = new byte[iv.length + ciphertext.length];
            System.arraycopy(iv, 0, combined, 0, iv.length);
            System.arraycopy(ciphertext, 0, combined, iv.length, ciphertext.length);

            return Base64.getEncoder().encodeToString(combined);
        } catch (Exception e) {
            throw new RuntimeException("加密失败: " + e.getMessage(), e);
        }
    }

    /**
     * 命令行入口：加密明文并输出 ENC(...) 格式。
     * <p>
     * 用法: java ... AesCrypto <明文> <加密密钥>
     */
    public static void main(String[] args) {
        if (args.length < 2 || args[0].isBlank() || args[1].isBlank()) {
            System.err.println("用法: AesCrypto <明文> <加密密钥>");
            System.exit(1);
        }

        String encrypted = encrypt(args[0], args[1]);
        System.out.println("加密成功！");
        System.out.println();
        System.out.println("请将以下值填入 application.properties:");
        System.out.println("  cap.secret-key=ENC(" + encrypted + ")");
    }

    /**
     * 解密 Base64 编码的密文（包含 IV），返回明文。
     */
    public static String decrypt(String encryptedBase64, String encryptionKey) {
        try {
            SecretKeySpec key = deriveKey(encryptionKey);
            byte[] combined = Base64.getDecoder().decode(encryptedBase64);

            byte[] iv = new byte[IV_LENGTH];
            byte[] ciphertext = new byte[combined.length - IV_LENGTH];
            System.arraycopy(combined, 0, iv, 0, IV_LENGTH);
            System.arraycopy(combined, IV_LENGTH, ciphertext, 0, ciphertext.length);

            Cipher cipher = Cipher.getInstance(ALGORITHM);
            cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(TAG_LENGTH, iv));

            byte[] plaintext = cipher.doFinal(ciphertext);
            return new String(plaintext, StandardCharsets.UTF_8);
        } catch (Exception e) {
            throw new RuntimeException("解密失败: " + e.getMessage(), e);
        }
    }
}
