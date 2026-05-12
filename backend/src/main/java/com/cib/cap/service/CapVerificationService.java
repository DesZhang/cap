package com.cib.cap.service;

import com.cib.cap.crypto.SecretResolver;
import com.cib.cap.model.VerifyResult;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

/**
 * Cap Token 验证服务
 * <p>
 * 调用 Cap Standalone 的 /siteverify 接口验证前端提交的 Token。
 * Cap 使用 getdel 原子操作消费 Token，天然防止重放攻击。
 */
@Service
public class CapVerificationService {

    private static final Logger log = LoggerFactory.getLogger(CapVerificationService.class);

    private final RestClient restClient;
    private final ObjectMapper objectMapper;
    private final String verifyUrl;
    private final String secretKey;

    public CapVerificationService(
            RestClient.Builder restClientBuilder,
            ObjectMapper objectMapper,
            @Value("${cap.instance-url:}") String capInstanceUrl,
            @Value("${cap.site-key:}") String siteKey,
            @Value("${cap.secret-key:}") String secretKey) {
        if (capInstanceUrl == null || capInstanceUrl.isBlank()) {
            throw new IllegalStateException("Cap 服务地址未配置，请在 application.properties 中设置 cap.instance-url");
        }
        if (siteKey == null || siteKey.isBlank()) {
            throw new IllegalStateException("Cap Site Key 未配置，请在 application.properties 中设置 cap.site-key");
        }
        if (secretKey == null || secretKey.isBlank()) {
            throw new IllegalStateException("Cap Secret Key 未配置，请在 application.properties 中设置 cap.secret-key");
        }

        this.secretKey = SecretResolver.resolve(secretKey);
        this.verifyUrl = capInstanceUrl + "/" + siteKey + "/siteverify";

        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(java.time.Duration.ofSeconds(5));
        factory.setReadTimeout(java.time.Duration.ofSeconds(10));
        this.restClient = restClientBuilder
                .requestFactory(factory)
                .build();
        this.objectMapper = objectMapper;

        log.info("Cap 验证服务已初始化: siteKey={}, verifyUrl={}", siteKey, verifyUrl);
    }

    private static final int MAX_RETRIES = 3;
    private static final long RETRY_DELAY_MS = 500;

    /**
     * 验证 Cap Token
     * <p>
     * 调用 Cap /siteverify 接口，失败时自动重试（最多 {@value MAX_RETRIES} 次）。
     */
    public VerifyResult verifyToken(String token) {
        if (token == null || token.isBlank()) {
            return VerifyResult.emptyToken();
        }

        for (int attempt = 1; attempt <= MAX_RETRIES; attempt++) {
            try {
                return doVerify(token);
            } catch (Exception e) {
                log.warn("Cap 验证请求失败 (attempt {}): {}", attempt, e.getMessage());
                if (attempt < MAX_RETRIES) {
                    try {
                        Thread.sleep(RETRY_DELAY_MS);
                    } catch (InterruptedException ie) {
                        Thread.currentThread().interrupt();
                        return VerifyResult.serviceUnavailable("请求被中断");
                    }
                }
            }
        }
        log.error("Cap 验证请求失败，已重试 {} 次", MAX_RETRIES);
        return VerifyResult.serviceUnavailable("重试耗尽");
    }

    /**
     * 执行单次验证请求。
     * <p>
     * Cap 在验证成功时原子删除 Token（getdel），重放、伪造、过期的 Token
     * 都会返回 "Token not found"，由调用方统一按验证失败处理。
     */
    private VerifyResult doVerify(String token) throws Exception {
        String requestBody = objectMapper.writeValueAsString(
                java.util.Map.of("secret", secretKey, "response", token)
        );

        String responseBody;
        try {
            responseBody = restClient.post()
                    .uri(verifyUrl)
                    .header("Content-Type", "application/json")
                    .body(requestBody)
                    .retrieve()
                    .body(String.class);
        } catch (org.springframework.web.client.HttpClientErrorException e) {
            responseBody = e.getResponseBodyAsString();
        } catch (org.springframework.web.client.HttpServerErrorException e) {
            responseBody = e.getResponseBodyAsString();
        }

        JsonNode json = objectMapper.readTree(responseBody);
        boolean success = json.has("success") && json.get("success").asBoolean();

        if (success) {
            return VerifyResult.success();
        }

        String capError = json.has("error") ? json.get("error").asText() : "unknown";
        log.info("Cap Token 验证失败: token={}, error={}", token.substring(0, Math.min(token.length(), 10)) + "...", capError);
        return VerifyResult.tokenInvalid(capError);
    }
}
