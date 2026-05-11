<template>
  <div id="app">
    <header>
      <h1>🛡️ Cap CAPTCHA 集成演示</h1>
      <p>Cap (trycap.dev) — 自托管 CAPTCHA 方案 · Spring Boot + Vue 集成示例</p>
    </header>

    <main>
      <div class="status-bar" :class="{ connected: capReady, disconnected: !capReady }">
        <span>{{ capReady ? '✅ Cap 服务已连接' : '⏳ 等待 Cap 服务连接...' }}</span>
      </div>

      <WidgetDemo :cap-api-endpoint="capApiEndpoint" />
      <ProgrammaticDemo :cap-api-endpoint="capApiEndpoint" />
      <InvisibleDemo :cap-api-endpoint="capApiEndpoint" />
      <AccessibilityDemo :cap-api-endpoint="capApiEndpoint" />
    </main>

    <footer>
      <p>
        <a href="https://trycap.dev" target="_blank">Cap 官网</a> ·
        <a href="https://github.com/tiagozip/cap" target="_blank">GitHub</a> ·
        <a href="https://capjs.js.org/guide" target="_blank">文档</a>
      </p>
    </footer>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue';
import WidgetDemo from './components/WidgetDemo.vue';
import ProgrammaticDemo from './components/ProgrammaticDemo.vue';
import InvisibleDemo from './components/InvisibleDemo.vue';
import AccessibilityDemo from './components/AccessibilityDemo.vue';

// Cap 服务端点配置
// 格式: http://<cap-host>:<port>/<site-key>/
// 本地开发默认值，需要替换为实际的 Site Key
const CAP_HOST = 'http://localhost:3000';
const SITE_KEY = import.meta.env.VITE_CAP_SITE_KEY || '';
const capApiEndpoint = computed(() => SITE_KEY ? `${CAP_HOST}/${SITE_KEY}/` : `${CAP_HOST}/`);

// 检查 Cap 服务是否可用
const capReady = ref(false);

onMounted(async () => {
  try {
    const response = await fetch(`${CAP_HOST}/${SITE_KEY}/`);
    capReady.value = response.ok || response.status === 200;
  } catch {
    capReady.value = false;
  }
});
</script>

<style>
* {
  box-sizing: border-box;
}

body {
  margin: 0;
  font-family: system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif;
  background: #f8f9fa;
  color: #333;
}

#app {
  max-width: 900px;
  margin: 0 auto;
  padding: 2rem;
}

header {
  text-align: center;
  margin-bottom: 2rem;
  padding-bottom: 1.5rem;
  border-bottom: 2px solid #e0e0e0;
}

header h1 {
  margin: 0 0 0.5rem 0;
  font-size: 1.8rem;
}

header p {
  color: #666;
  margin: 0;
}

.status-bar {
  text-align: center;
  padding: 0.75rem;
  border-radius: 6px;
  margin-bottom: 2rem;
  font-size: 0.9rem;
}
.status-bar.connected {
  background: #e8f5e9;
  color: #2e7d32;
}
.status-bar.disconnected {
  background: #fff3e0;
  color: #e65100;
}

.demo-section {
  background: white;
  border-radius: 8px;
  padding: 1.5rem;
  margin-bottom: 1.5rem;
  box-shadow: 0 1px 3px rgba(0,0,0,0.1);
}

.demo-section h2 {
  margin-top: 0;
  font-size: 1.2rem;
}

.description {
  color: #555;
  font-size: 0.9rem;
  line-height: 1.5;
}

.description code {
  background: #f0f0f0;
  padding: 0.1em 0.3em;
  border-radius: 3px;
  font-size: 0.85em;
}

.code-hint {
  background: #263238;
  color: #aed581;
  padding: 1rem;
  border-radius: 6px;
  margin: 1rem 0;
  overflow-x: auto;
}

.code-hint pre {
  margin: 0;
}

.code-hint code {
  font-family: 'Fira Code', 'Consolas', monospace;
  font-size: 0.82rem;
  line-height: 1.5;
}

.demo-form,
.demo-controls {
  margin-top: 1rem;
}

.widget-container {
  margin-bottom: 1rem;
}

.token-display {
  background: #e3f2fd;
  padding: 0.75rem;
  border-radius: 6px;
  margin: 0.75rem 0;
  font-size: 0.85rem;
}

.token-display code {
  display: block;
  margin-top: 0.25rem;
  word-break: break-all;
  color: #1565c0;
}

button {
  background: #1976d2;
  color: white;
  border: none;
  padding: 0.6rem 1.5rem;
  border-radius: 6px;
  cursor: pointer;
  font-size: 0.9rem;
  transition: background 0.2s;
}

button:hover:not(:disabled) {
  background: #1565c0;
}

button:disabled {
  background: #bdbdbd;
  cursor: not-allowed;
}

footer {
  text-align: center;
  padding-top: 1.5rem;
  border-top: 1px solid #e0e0e0;
  color: #999;
  font-size: 0.85rem;
}

footer a {
  color: #1976d2;
  text-decoration: none;
}

footer a:hover {
  text-decoration: underline;
}
</style>
