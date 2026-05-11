<template>
  <section class="demo-section">
    <h2>🟣 无障碍模式（Accessibility）</h2>
    <p class="description">
      Cap 不依赖视觉谜题或图像识别，天然支持无障碍访问。Widget 组件支持键盘导航和
      屏幕阅读器，无需额外配置。
    </p>

    <div class="accessibility-notes">
      <h3>Cap 的无障碍特性：</h3>
      <ul>
        <li><strong>无视觉谜题</strong> — 不需要用户识别图片、选择红绿灯或输入扭曲文字</li>
        <li><strong>键盘可访问</strong> — 所有交互均可通过键盘完成</li>
        <li><strong>屏幕阅读器兼容</strong> — Widget 提供适当的 ARIA 标签</li>
        <li><strong>无额外操作</strong> — 用户无需执行超出正常浏览器的操作</li>
        <li><strong>隐私友好</strong> — 不追踪用户行为，不收集个人数据</li>
      </ul>
    </div>

    <div class="code-hint">
      <pre><code>&lt;!-- 无障碍模式与标准 Widget 完全相同 --&gt;
&lt;!-- Cap 通过 SHA-256 工作量证明 + JS 环境检测验证用户 --&gt;
&lt;!-- 无需任何额外配置，所有用户获得相同的无障碍体验 --&gt;

&lt;cap-widget
  data-cap-api-endpoint="{{ capApiEndpoint }}"
&gt;&lt;/cap-widget&gt;</code></pre>
    </div>

    <form @submit.prevent="onSubmit" class="demo-form">
      <div ref="widgetContainer" class="widget-container" role="region" aria-label="CAPTCHA 验证区域"></div>
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

<style scoped>
.accessibility-notes {
  background: #f3e5f5;
  padding: 1rem;
  border-radius: 6px;
  margin-bottom: 1rem;
}
.accessibility-notes h3 {
  margin-top: 0;
  font-size: 0.95rem;
}
.accessibility-notes ul {
  margin: 0.5rem 0 0 0;
  padding-left: 1.5rem;
}
.accessibility-notes li {
  margin-bottom: 0.3rem;
  font-size: 0.85rem;
}
</style>
