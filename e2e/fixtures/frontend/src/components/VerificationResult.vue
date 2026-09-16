<template>
  <div class="verification-result" :class="{ success: result.success, failure: !result.success }">
    <span class="icon">{{ result.success ? '✅' : '❌' }}</span>
    <span class="message">{{ result.message }}</span>
  </div>
</template>

<script setup>
defineProps({
  result: {
    type: Object,
    required: true,
    validator: (val) => typeof val.success === 'boolean' && typeof val.message === 'string',
  },
});
</script>

<style scoped>
.verification-result {
  margin-top: 0.75rem;
  padding: 0.75rem 1rem;
  border-radius: 6px;
  font-size: 0.9rem;
  display: flex;
  align-items: center;
  gap: 0.5rem;
}
.verification-result.success {
  background: #e8f5e9;
  color: #2e7d32;
}
.verification-result.failure {
  background: #fbe9e7;
  color: #c62828;
}
.icon {
  font-size: 1.1rem;
}
</style>
