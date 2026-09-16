/**
 * Cap Token 验证 API 服务
 * 调用 Spring Boot 后端的 /api/cap/verify 接口验证 Token
 *
 * 后端仅通过 HTTP 状态码表达结果，无响应体：
 * - 200: 验证通过
 * - 400: Token 为空
 * - 401: Token 无效（伪造、过期、重放）
 * - 503: Cap 服务不可用
 */

const API_BASE = '/api/cap';

const STATUS_MESSAGES = {
  400: 'Token 不能为空',
  401: '验证失败，请重试',
  503: '验证服务暂时不可用，请稍后再试',
};

/**
 * 验证 Cap Token
 * @param {string} token - 前端获取的 Cap Token
 * @returns {Promise<{success: boolean, message: string}>}
 */
export async function verifyToken(token) {
  const response = await fetch(`${API_BASE}/verify`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ token }),
  });

  if (response.ok) {
    return { success: true, message: '验证成功' };
  }

  return {
    success: false,
    message: STATUS_MESSAGES[response.status] || `请求失败 (${response.status})`,
  };
}
