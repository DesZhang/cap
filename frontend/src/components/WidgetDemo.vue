<template>
  <section class="demo-section">
    <h2>🔵 Widget 模式（标准组件）</h2>
    <p class="description">
      在表单中嵌入 <code>&lt;cap-widget&gt;</code> 组件，用户完成验证后自动注入隐藏的 Token 字段。
      这是最常用的集成方式。
    </p>

    <div class="code-hint">
      <pre><code>&lt;!-- 加载 Cap Widget 脚本 --&gt;
&lt;script src="http://localhost:3000/assets/widget.js"&gt;&lt;/script&gt;

&lt;!-- 在表单中嵌入 Widget --&gt;
&lt;form @submit="onSubmit"&gt;
  &lt;cap-widget
    data-cap-api-endpoint="{{ capApiEndpoint }}"
  &gt;&lt;/cap-widget&gt;
  &lt;button type="submit"&gt;提交&lt;/button&gt;
&lt;/form&gt;</code></pre>
    </div>

    <form @submit.prevent="onSubmit" class="demo-form">
      <div ref="widgetContainer" class="widget-container"></div>
      <button type="submit" :disabled="loading">
        {{ loading ? '验证中...' : '提交并验证' }}
      </button>
    </form>

    <VerificationResult v-if="result" :result="result" />
  </section>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue';
import { verifyToken } from '../services/cap-verify.js';
import VerificationResult from './VerificationResult.vue';

const props = defineProps({
  capApiEndpoint: { type: String, required: true },
});

const widgetContainer = ref(null);
const loading = ref(false);
const result = ref(null);
let widget = null;

onMounted(() => {
  // 检查 Cap Widget 脚本是否已加载
  if (!customElements.get('cap-widget')) {
    widgetContainer.value.innerHTML = '<p style="color: #c62828;">⚠️ Cap Widget 脚本未加载。请确保 Cap 服务正在运行（http://localhost:3000）并刷新页面。</p>';
    return;
  }
  // 动态创建 cap-widget 组件
  widget = document.createElement('cap-widget');
  widget.setAttribute('data-cap-api-endpoint', props.capApiEndpoint);
  widgetContainer.value.appendChild(widget);
});

onUnmounted(() => {
  if (widget && widgetContainer.value) {
    widgetContainer.value.removeChild(widget);
  }
});

async function onSubmit() {
  loading.value = true;
  result.value = null;

  try {
    // cap-widget 会自动注入隐藏的 cap-token 输入框
    const tokenInput = widgetContainer.value.querySelector('input[name="cap-token"]');
    const token = tokenInput?.value;

    if (!token) {
      result.value = { success: false, message: '请先完成 CAPTCHA 验证' };
      return;
    }

    result.value = await verifyToken(token);
  } catch (err) {
    result.value = { success: false, message: `错误: ${err.message}` };
  } finally {
    loading.value = false;
  }
}
</script>
