const form = document.getElementById('deployForm');
const subscriptionSelect = document.getElementById('subscriptionSelect');
const subscriptionId = document.getElementById('subscriptionId');
const subscriptionMessage = document.getElementById('subscriptionMessage');
const consoleEl = document.getElementById('console');
const statusBadge = document.getElementById('statusBadge');
const spinner = document.getElementById('spinner');
const deployBtn = document.getElementById('deployBtn');
const whatIfBtn = document.getElementById('whatIfBtn');
const userCount = document.getElementById('userCount');
const deploySqlMi = document.getElementById('deploySqlMi');
let eventSource;

function setStatus(status) {
  statusBadge.textContent = status.charAt(0).toUpperCase() + status.slice(1);
  statusBadge.className = `badge ${status}`;
  spinner.classList.toggle('hidden', status !== 'running');
  deployBtn.disabled = status === 'running';
  whatIfBtn.disabled = status === 'running';
}

function appendLog(text, stream = 'stdout') {
  if (consoleEl.textContent === 'Ready.') consoleEl.textContent = '';
  const prefix = stream === 'stderr' ? '[err] ' : stream === 'system' ? '[system] ' : '';
  consoleEl.textContent += prefix + text;
  consoleEl.scrollTop = consoleEl.scrollHeight;
}

function updateEstimate() {
  const students = Math.min(50, Math.max(1, Number(userCount.value || 1)));
  const sqlVm = students * 0.76;
  const bastion = 0.19;
  const sqlMi = deploySqlMi.checked ? students * 0.75 : 0;
  const total = sqlVm + bastion + sqlMi;
  document.getElementById('estimateStudents').textContent = String(students);
  document.getElementById('estimateVm').textContent = `$${sqlVm.toFixed(2)}/h`;
  document.getElementById('estimateMi').textContent = `$${sqlMi.toFixed(2)}/h`;
  document.getElementById('estimateTotal').textContent = `$${total.toFixed(2)}/h`;
  document.getElementById('estimateWarning').textContent =
    deploySqlMi.checked && students >= 30
      ? 'SQL Managed Instance at this scale is slow and costly. Confirm quota and budget first.'
      : '';
}

function collectPayload() {
  return {
    subscriptionId: subscriptionId.value.trim(),
    tenantId: document.getElementById('tenantId').value.trim(),
    userCount: Number(userCount.value),
    startIndex: Number(document.getElementById('startIndex').value),
    location: document.getElementById('location').value,
    prefix: document.getElementById('prefix').value.trim(),
    vmAdminPassword: document.getElementById('vmAdminPassword').value,
    sqlAdminPassword: document.getElementById('sqlAdminPassword').value,
    deploySqlMi: deploySqlMi.checked,
    deploySourceVm: document.getElementById('deploySourceVm').checked,
    createUsers: document.getElementById('createUsers').checked,
    securityControlIgnore: document.getElementById('securityControlIgnore').checked
  };
}

async function startJob(endpoint, payloadOverride, skipFormValidation) {
  if (!skipFormValidation && !form.reportValidity()) return;
  if (eventSource) eventSource.close();
  consoleEl.textContent = '';
  setStatus('running');
  try {
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payloadOverride || collectPayload())
    });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || 'Request failed.');
    appendLog(`Connected to job ${result.jobId}\n`, 'system');
    eventSource = new EventSource(`/api/stream/${result.jobId}`);
    eventSource.addEventListener('log', event => {
      const entry = JSON.parse(event.data);
      appendLog(entry.text, entry.stream);
    });
    eventSource.addEventListener('status', event => {
      const state = JSON.parse(event.data);
      setStatus(state.status);
      if (state.status !== 'running' && eventSource) eventSource.close();
    });
    eventSource.onerror = () => appendLog('Log stream disconnected.\n', 'stderr');
  } catch (err) {
    appendLog(`${err.message}\n`, 'stderr');
    setStatus('failed');
  }
}

async function loadSubscriptions() {
  try {
    const response = await fetch('/api/subscriptions');
    const data = await response.json();
    subscriptionSelect.innerHTML = '<option value="">Select a subscription or enter manually…</option>';
    for (const sub of data.subscriptions || []) {
      const option = document.createElement('option');
      option.value = sub.id;
      option.textContent = `${sub.name} (${sub.id})`;
      subscriptionSelect.appendChild(option);
    }
    subscriptionMessage.textContent = data.message || '';
  } catch {
    subscriptionSelect.innerHTML = '<option value="">Enter subscription manually…</option>';
    subscriptionMessage.textContent = 'Could not load Azure subscriptions.';
  }
}

subscriptionSelect.addEventListener('change', () => {
  if (subscriptionSelect.value) subscriptionId.value = subscriptionSelect.value;
});
userCount.addEventListener('input', updateEstimate);
deploySqlMi.addEventListener('change', updateEstimate);
form.addEventListener('submit', event => {
  event.preventDefault();
  startJob('/api/deploy');
});
whatIfBtn.addEventListener('click', () => startJob('/api/whatif'));

const detectIndexBtn = document.getElementById('detectIndexBtn');
const detectIndexMessage = document.getElementById('detectIndexMessage');
detectIndexBtn.addEventListener('click', async () => {
  const sub = subscriptionId.value.trim();
  const prefix = document.getElementById('prefix').value.trim();
  if (!sub) { detectIndexMessage.textContent = 'Enter a Subscription ID first.'; return; }
  if (!prefix) { detectIndexMessage.textContent = 'Enter a resource prefix first.'; return; }
  detectIndexMessage.textContent = 'Detecting…';
  detectIndexBtn.disabled = true;
  try {
    const params = new URLSearchParams({ subscriptionId: sub, prefix });
    const response = await fetch(`/api/next-index?${params.toString()}`);
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || 'Request failed.');
    document.getElementById('startIndex').value = String(data.nextIndex);
    detectIndexMessage.textContent = data.message
      ? data.message
      : data.highestIndex > 0
        ? `Highest existing student is ${data.highestIndex}; next free index is ${data.nextIndex}.`
        : `No existing students found; start index set to ${data.nextIndex}.`;
  } catch (err) {
    detectIndexMessage.textContent = err.message;
  } finally {
    detectIndexBtn.disabled = false;
  }
});

const cleanupBtn = document.getElementById('cleanupBtn');
cleanupBtn.addEventListener('click', () => {
  const sub = subscriptionId.value.trim();
  const prefix = document.getElementById('prefix').value.trim();
  if (!sub) { alert('Enter a Subscription ID in the form above first.'); return; }
  if (!prefix) { alert('Enter a resource prefix in the form above first.'); return; }
  const deleteUsers = document.getElementById('cleanupDeleteUsers').checked;
  const tenantDomain = document.getElementById('cleanupTenantDomain').value.trim();
  if (deleteUsers && !tenantDomain) { alert('Tenant domain is required to delete users.'); return; }
  const confirmMsg = `This deletes ALL resource groups rg-${prefix}-user* in subscription ${sub}` +
    (deleteUsers ? ` and the Entra users ${prefix}user*@${tenantDomain}` : '') + '.\n\nContinue?';
  if (!confirm(confirmMsg)) return;
  startJob('/api/cleanup', { subscriptionId: sub, prefix, deleteUsers, tenantDomain }, true);
});

updateEstimate();
loadSubscriptions();
