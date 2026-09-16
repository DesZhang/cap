package com.cib.cap.controller;

import com.cib.cap.model.CapVerifyRequest;
import com.cib.cap.model.VerifyResult;
import com.cib.cap.service.CapVerificationService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

/**
 * Cap 验证控制器
 * <p>
 * POST /api/cap/verify — 200 表示验证通过，4xx 表示失败。
 * 响应体为空，不给攻击者任何信息。
 */
@RestController
@RequestMapping("/api/cap")
public class CapController {

    private static final Logger log = LoggerFactory.getLogger(CapController.class);

    private final CapVerificationService verificationService;

    public CapController(CapVerificationService verificationService) {
        this.verificationService = verificationService;
    }

    /**
     * 验证 Cap Token
     * <p>
     * POST /api/cap/verify
     * 请求体: { "token": "cap_token_string" }
     * <p>
     * - 200: 验证通过
     * - 400: Token 为空
     * - 401: Token 无效（伪造、过期、重放）
     * - 503: Cap 服务不可用
     */
    @PostMapping("/verify")
    public ResponseEntity<Void> verify(@RequestBody CapVerifyRequest request) {
        VerifyResult result = verificationService.verifyToken(request.getToken());

        if (result.isSuccess()) {
            log.info("Cap 验证通过");
            return ResponseEntity.ok().build();
        }

        log.warn("Cap 验证失败: status={}, detail={}", result.getStatus(), result.getDetail());

        return switch (result.getStatus()) {
            case EMPTY_TOKEN -> ResponseEntity.badRequest().build();
            case TOKEN_INVALID -> ResponseEntity.status(401).build();
            case SERVICE_UNAVAILABLE -> ResponseEntity.status(503).build();
            default -> ResponseEntity.status(401).build();
        };
    }
}
