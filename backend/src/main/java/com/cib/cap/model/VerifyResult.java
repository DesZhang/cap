package com.cib.cap.model;

/**
 * Cap Token 验证结果（内部使用）
 * <p>
 * 携带验证状态和原因，供调用方根据状态做后续处理（放行、拦截、记录日志等）。
 * 不直接暴露给前端。
 */
public class VerifyResult {

    public enum Status {
        /** 验证通过 */
        SUCCESS,
        /** Token 为空或格式不正确 */
        EMPTY_TOKEN,
        /** Token 不存在、已过期、或已被消费（重放） */
        TOKEN_INVALID,
        /** Cap 服务不可用（网络错误、重试耗尽） */
        SERVICE_UNAVAILABLE
    }

    private final Status status;
    private final String detail;

    private VerifyResult(Status status, String detail) {
        this.status = status;
        this.detail = detail;
    }

    public Status getStatus() {
        return status;
    }

    public String getDetail() {
        return detail;
    }

    public boolean isSuccess() {
        return status == Status.SUCCESS;
    }

    // --- 静态工厂方法 ---

    public static VerifyResult success() {
        return new VerifyResult(Status.SUCCESS, "验证通过");
    }

    public static VerifyResult emptyToken() {
        return new VerifyResult(Status.EMPTY_TOKEN, "Token 为空");
    }

    public static VerifyResult tokenInvalid(String detail) {
        return new VerifyResult(Status.TOKEN_INVALID, detail != null ? detail : "Token 无效");
    }

    public static VerifyResult serviceUnavailable(String detail) {
        return new VerifyResult(Status.SERVICE_UNAVAILABLE, detail);
    }
}
