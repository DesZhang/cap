<template>
  <section class="demo-section">
    <h2>🟢 编程模式（Programmatic）</h2>
    <p class="description">
      通过 JavaScript API 静默获取 Token，无需可见的 Widget 组件。适用于 API 调用、
      后台操作或需要完全无感验证的场景。
    </p>

    <div class="code-hint">
      <pre><code>import { Cap } from 'cap-widget';

const cap = new Cap({
  apiEndpoint: '{{ capApiEndpoint }}'
});

// 监听进度
const offProgress = cap.addEventListener('progress', (e) => {
  console.log(`验证进度: ${e.detail.progress}%`);
});

// 静默求解并获取 Token
const { token } = await cap.solve();
// 将 token 发送到后端验证</code></pre>
    </div>

    <div class="demo-controls">
      <button @click="solve" :disabled="loading || solving">
        {{ solving ? `求解中 (${progress}%)...` : '静默获取 Token' }}
      </button>
    </div>

    <div v-if="token" class="token-display">
      <strong>获取到的 Token:</strong>
      <code>{{ token.substring(0, 40) }}...</code>
    </div>

    <button v-if="token" @click="verify" :disabled="loading">
      {{ loading ? '验证中...' : '验证 Token' }}
    </button>

    <VerificationResult v-if="result" :result="result" />
  </section>
</template>

<script setup>
import { ref } from 'vue';
import { verifyToken } from '../services/cap-verify.js';
import VerificationResult from './VerificationResult.vue';

const props = defineProps({
  capApiEndpoint: { type: String, required: true },
});

const solving = ref(false);
const loading = ref(false);
const progress = ref(0);
const token = ref('');
const result = ref(null);

async function solve() {
  solving.value = true;
  progress.value = 0;
  token.value = '';
  result.value = null;

  try {
    // 使用 Cap 编程 API
    if (!window.Cap) {
      result.value = { success: false, message: 'Cap 组件未加载，请检查 Cap 服务是否正在运行' };
      return;
    }
    const cap = new window.Cap({ apiEndpoint: props.capApiEndpoint });

    cap.addEventListener('progress', (e) => {
      progress.value = Math.round(e.detail.progress);
    });

    const solution = await cap.solve();
    token.value = solution.token;
  } catch (err) {
    result.value = { success: false, message: `求解失败: ${err.message}` };
  } finally {
    solving.value = false;
  }
}

async function verify() {
  if (!token.value) return;

  loading.value = true;
  try {
    result.value = await verifyToken(token.value);
  } catch (err) {
    result.value = { success: false, message: `错误: ${err.message}` };
  } finally {
    loading.value = false;
  }
}
</script>
