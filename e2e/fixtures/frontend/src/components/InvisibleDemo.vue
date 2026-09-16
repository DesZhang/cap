<template>
  <section class="demo-section">
    <h2>🟡 浮动/隐形模式（Invisible/Floating）</h2>
    <p class="description">
      Widget 隐藏在触发按钮旁边，用户点击按钮后弹出验证。适用于不想在页面中常驻
      CAPTCHA 组件的场景。
    </p>

    <div class="code-hint">
      <pre><code>&lt;!-- 浮动模式：触发按钮指向 Widget --&gt;
&lt;cap-widget
  id="floating-widget"
  data-cap-api-endpoint="{{ capApiEndpoint }}"
&gt;&lt;/cap-widget&gt;

&lt;button
  data-cap-floating="#floating-widget"
  data-cap-floating-position="bottom"
&gt;触发验证&lt;/button&gt;</code></pre>
    </div>

    <div ref="widgetContainer" class="widget-container"></div>

    <div class="demo-controls">
      <button
        ref="triggerBtn"
        data-cap-floating="#floating-widget"
        data-cap-floating-position="bottom"
        :disabled="loading"
      >
        {{ loading ? '验证中...' : '触发浮动验证' }}
      </button>
    </div>

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
  // 创建浮动模式的 widget
  widget = document.createElement('cap-widget');
  widget.id = 'floating-widget';
  widget.setAttribute('data-cap-api-endpoint', props.capApiEndpoint);
  widgetContainer.value.appendChild(widget);

  // 监听完成事件
  widget.addEventListener('solve', (e) => {
    handleComplete(e.detail?.token);
  });
});

onUnmounted(() => {
  if (widget && widgetContainer.value) {
    widgetContainer.value.removeChild(widget);
  }
});

function onTrigger() {
  // 浮动 widget 由 floating.js 自动处理触发
  // solve 事件会捕获 token
}

async function handleComplete(capToken) {
  if (!capToken) return;

  loading.value = true;
  result.value = null;

  try {
    result.value = await verifyToken(capToken);
  } catch (err) {
    result.value = { success: false, message: `错误: ${err.message}` };
  } finally {
    loading.value = false;
  }
}
</script>
