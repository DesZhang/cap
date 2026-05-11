package com.cib.cap.crypto;

/**
 * 加密配置属性解析器
 * <p>
 * 识别 application.properties 中的 ENC(...) 格式并自动解密。
 * <p>
 * 行为：
 * - 如果值为 ENC(xxx) 格式，使用 CAP_ENCRYPTION_KEY 环境变量解密
 * - 如果值为明文（无 ENC 前缀），原样返回（本地开发兼容）
 */
public class SecretResolver {

    private static final String ENV_KEY = "CAP_ENCRYPTION_KEY";
    private static final String ENC_PREFIX = "ENC(";
    private static final String ENC_SUFFIX = ")";

    /**
     * 解析秘密值：从环境变量读取加密密钥，ENC(...) 格式自动解密，其他值原样返回。
     */
    public static String resolve(String rawValue) {
        return resolve(rawValue, System.getenv(ENV_KEY));
    }

    /**
     * 解析秘密值：ENC(...) 格式使用指定密钥解密，其他值原样返回。
     *
     * @param rawValue      application.properties 中的原始值
     * @param encryptionKey 加密密钥（可为 null，表示明文模式）
     * @return 解密后的明文（或原始明文值）
     */
    public static String resolve(String rawValue, String encryptionKey) {
        if (rawValue == null || !rawValue.startsWith(ENC_PREFIX) || !rawValue.endsWith(ENC_SUFFIX)) {
            return rawValue;
        }

        if (encryptionKey == null || encryptionKey.isBlank()) {
            throw new IllegalStateException(
                    "配置值已加密 (ENC 格式)，但未设置环境变量 " + ENV_KEY + "。"
                            + "请设置加密密钥或使用明文配置。");
        }

        String encryptedContent = rawValue.substring(ENC_PREFIX.length(), rawValue.length() - ENC_SUFFIX.length());
        return AesCrypto.decrypt(encryptedContent, encryptionKey);
    }
}
