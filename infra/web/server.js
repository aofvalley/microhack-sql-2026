'use strict';

const express = require('express');
const path = require('path');
const { spawn } = require('child_process');
const crypto = require('crypto');

const app = express();
const host = process.env.HOST || '127.0.0.1';
const port = Number(process.env.PORT || 3000);
const appPassword = process.env.APP_PASSWORD || '';
const appUsername = process.env.APP_USERNAME || 'admin';
const isLocalHost = host === '127.0.0.1' || host === 'localhost' || host === '::1';

// Refuse to start exposed (non-loopback) without a password. Inside a container
// the app binds 0.0.0.0, so APP_PASSWORD is mandatory there.
if (!isLocalHost && !appPassword) {
  console.error('Refusing to start: HOST is not loopback and APP_PASSWORD is not set. Set APP_PASSWORD to protect the deployer.');
  process.exit(1);
}

function safeEqual(a, b) {
  const bufA = Buffer.from(String(a));
  const bufB = Buffer.from(String(b));
  if (bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}

// HTTP Basic auth gate. Enabled whenever APP_PASSWORD is set. Behind a trusted
// boundary only (see README): provides a password gate, not full hardening.
function requireAuth(req, res, next) {
  if (!appPassword) return next();
  const header = req.headers.authorization || '';
  const [scheme, encoded] = header.split(' ');
  if (scheme === 'Basic' && encoded) {
    const decoded = Buffer.from(encoded, 'base64').toString('utf8');
    const sep = decoded.indexOf(':');
    const user = decoded.slice(0, sep);
    const pass = decoded.slice(sep + 1);
    if (safeEqual(user, appUsername) && safeEqual(pass, appPassword)) return next();
  }
  res.set('WWW-Authenticate', 'Basic realm="MicroHack SQL 2026 Lab Deployer", charset="UTF-8"');
  res.status(401).send('Authentication required.');
}
const repoRoot = path.resolve(__dirname, '..');
const publicDir = path.join(__dirname, 'public');
const deployScript = path.join(repoRoot, 'scripts', 'deploy.ps1');
const cleanupScript = path.join(repoRoot, 'scripts', 'cleanup.ps1');
// On Windows the Azure CLI is a batch wrapper (az.cmd); Node refuses to spawn .cmd files
// without a shell, so run az through a shell there. In the Linux container az is a real
// binary. All values passed to az below are validated (GUID subscription id, alphanumeric
// prefix) or static, so shell use does not introduce injection.
const azSpawnOptions = { cwd: repoRoot, windowsHide: true, shell: process.platform === 'win32' };
const guidPattern = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
const jobs = new Map();

app.use(express.json({ limit: '32kb' }));
app.use(requireAuth);
app.use(express.static(publicDir));

function addJobLine(job, stream, chunk) {
  const text = chunk.toString();
  const entry = { at: new Date().toISOString(), stream, text };
  job.logs.push(entry);
  if (job.logs.length > 5000) job.logs.shift();
  const payload = `event: log\ndata: ${JSON.stringify(entry)}\n\n`;
  for (const res of job.clients) res.write(payload);
}

function broadcastStatus(job) {
  const payload = `event: status\ndata: ${JSON.stringify({
    jobId: job.id,
    status: job.status,
    exitCode: job.exitCode,
    startedAt: job.startedAt,
    finishedAt: job.finishedAt
  })}\n\n`;
  for (const res of job.clients) res.write(payload);
}

function parseBoolean(value, defaultValue = false) {
  if (typeof value === 'boolean') return value;
  if (value === undefined || value === null || value === '') return defaultValue;
  return String(value).toLowerCase() === 'true';
}

function validateDeployment(body) {
  const errors = [];
  const subscriptionId = String(body.subscriptionId || '').trim();
  const tenantId = String(body.tenantId || '').trim();
  const location = String(body.location || '').trim().toLowerCase();
  const prefix = String(body.prefix || '').trim();
  const userCount = Number(body.userCount);
  const startIndex = Number(body.startIndex);

  if (!subscriptionId) errors.push('Subscription ID is required.');
  if (!tenantId) errors.push('Tenant ID is required.');
  if (!location) errors.push('Location is required.');
  if (!Number.isInteger(userCount) || userCount < 1 || userCount > 50) {
    errors.push('Number of students must be an integer between 1 and 50.');
  }
  if (!Number.isInteger(startIndex) || startIndex < 1) {
    errors.push('Start index must be a positive integer.');
  }
  if (!/^[a-z0-9]{1,8}$/.test(prefix)) {
    errors.push('Resource prefix must be lowercase alphanumeric and at most 8 characters.');
  }

  if (errors.length) {
    const err = new Error(errors.join(' '));
    err.statusCode = 400;
    throw err;
  }

  return {
    subscriptionId,
    tenantId,
    location,
    prefix,
    userCount,
    startIndex,
    vmAdminPassword: String(body.vmAdminPassword || ''),
    sqlAdminPassword: String(body.sqlAdminPassword || ''),
    deploySqlMi: parseBoolean(body.deploySqlMi, true),
    deploySourceVm: parseBoolean(body.deploySourceVm, true),
    createUsers: parseBoolean(body.createUsers, false),
    whatIf: parseBoolean(body.whatIf, false),
    securityControlIgnore: parseBoolean(body.securityControlIgnore, false),
    setupScriptUri: String(body.setupScriptUri || process.env.SETUP_SCRIPT_URI || '').trim()
  };
}

function buildDeployArgs(input, forceWhatIf) {
  const args = [
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    deployScript,
    '-SubscriptionId',
    input.subscriptionId,
    '-TenantId',
    input.tenantId,
    '-UserCount',
    String(input.userCount),
    '-StartIndex',
    String(input.startIndex),
    '-Location',
    input.location,
    '-Prefix',
    input.prefix,
    '-DeploySqlMi',
    input.deploySqlMi ? 'true' : 'false',
    '-DeploySourceVm',
    input.deploySourceVm ? 'true' : 'false'
  ];

  if (input.vmAdminPassword) args.push('-VmAdminPassword', input.vmAdminPassword);
  if (input.sqlAdminPassword) args.push('-SqlAdminPassword', input.sqlAdminPassword);
  if (input.createUsers) args.push('-CreateUsers');
  if (forceWhatIf || input.whatIf) args.push('-WhatIf');
  if (input.securityControlIgnore) args.push('-SecurityControlIgnore');
  if (input.setupScriptUri) args.push('-SetupScriptUri', input.setupScriptUri);
  return args;
}

function startDeployment(body, forceWhatIf = false) {
  const input = validateDeployment(body);
  const id = crypto.randomUUID();
  const job = {
    id,
    status: 'running',
    exitCode: null,
    startedAt: new Date().toISOString(),
    finishedAt: null,
    logs: [],
    clients: new Set()
  };
  jobs.set(id, job);

  const args = buildDeployArgs(input, forceWhatIf);
  const child = spawn('pwsh', args, {
    cwd: repoRoot,
    windowsHide: true,
    env: process.env
  });
  job.processId = child.pid;

  addJobLine(job, 'system', `Starting ${forceWhatIf || input.whatIf ? 'what-if preview' : 'deployment'} job ${id}\n`);
  child.stdout.on('data', chunk => addJobLine(job, 'stdout', chunk));
  child.stderr.on('data', chunk => addJobLine(job, 'stderr', chunk));
  child.on('error', err => {
    job.status = 'failed';
    job.exitCode = -1;
    job.finishedAt = new Date().toISOString();
    addJobLine(job, 'stderr', `${err.message}\n`);
    broadcastStatus(job);
  });
  child.on('close', code => {
    job.status = code === 0 ? 'succeeded' : 'failed';
    job.exitCode = code;
    job.finishedAt = new Date().toISOString();
    addJobLine(job, 'system', `Process exited with code ${code}\n`);
    broadcastStatus(job);
  });

  return job;
}

app.post('/api/deploy', (req, res) => {
  try {
    const job = startDeployment(req.body, false);
    res.status(202).json({ jobId: job.id, status: job.status });
  } catch (err) {
    res.status(err.statusCode || 500).json({ error: err.message });
  }
});

app.post('/api/whatif', (req, res) => {
  try {
    const job = startDeployment({ ...req.body, whatIf: true }, true);
    res.status(202).json({ jobId: job.id, status: job.status });
  } catch (err) {
    res.status(err.statusCode || 500).json({ error: err.message });
  }
});

function validateCleanup(body) {
  const errors = [];
  const subscriptionId = String(body.subscriptionId || '').trim();
  const prefix = String(body.prefix || '').trim();
  if (!subscriptionId) errors.push('Subscription ID is required.');
  if (!/^[a-z0-9]{1,8}$/.test(prefix)) errors.push('Prefix must be 1-8 lowercase alphanumeric characters.');
  if (errors.length) {
    const err = new Error(errors.join(' '));
    err.statusCode = 400;
    throw err;
  }
  return {
    subscriptionId,
    prefix,
    deleteUsers: parseBoolean(body.deleteUsers, false),
    tenantDomain: String(body.tenantDomain || '').trim()
  };
}

function startCleanup(body) {
  const input = validateCleanup(body);
  if (input.deleteUsers && !input.tenantDomain) {
    const err = new Error('Tenant domain is required when deleting Entra users.');
    err.statusCode = 400;
    throw err;
  }

  const id = crypto.randomUUID();
  const job = {
    id,
    status: 'running',
    exitCode: null,
    startedAt: new Date().toISOString(),
    finishedAt: null,
    logs: [],
    clients: new Set()
  };
  jobs.set(id, job);

  // -All discovers every rg-<prefix>-user* group; -Force skips the interactive prompt.
  const args = [
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', cleanupScript,
    '-SubscriptionId', input.subscriptionId,
    '-Prefix', input.prefix,
    '-All', '-Force'
  ];
  if (input.deleteUsers) args.push('-DeleteUsers', '-TenantDomain', input.tenantDomain);

  const child = spawn('pwsh', args, { cwd: repoRoot, windowsHide: true, env: process.env });
  job.processId = child.pid;
  addJobLine(job, 'system', `Starting cleanup job ${id} for prefix ${input.prefix}\n`);
  child.stdout.on('data', chunk => addJobLine(job, 'stdout', chunk));
  child.stderr.on('data', chunk => addJobLine(job, 'stderr', chunk));
  child.on('error', err => {
    job.status = 'failed';
    job.exitCode = -1;
    job.finishedAt = new Date().toISOString();
    addJobLine(job, 'stderr', `${err.message}\n`);
    broadcastStatus(job);
  });
  child.on('close', code => {
    job.status = code === 0 ? 'succeeded' : 'failed';
    job.exitCode = code;
    job.finishedAt = new Date().toISOString();
    addJobLine(job, 'system', `Process exited with code ${code}\n`);
    broadcastStatus(job);
  });

  return job;
}

app.post('/api/cleanup', (req, res) => {
  try {
    const job = startCleanup(req.body);
    res.status(202).json({ jobId: job.id, status: job.status });
  } catch (err) {
    res.status(err.statusCode || 500).json({ error: err.message });
  }
});

app.get('/api/stream/:jobId', (req, res) => {
  const job = jobs.get(req.params.jobId);
  if (!job) return res.status(404).json({ error: 'Job not found.' });

  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    Connection: 'keep-alive',
    'X-Accel-Buffering': 'no'
  });
  res.write(`event: status\ndata: ${JSON.stringify({
    jobId: job.id,
    status: job.status,
    exitCode: job.exitCode,
    startedAt: job.startedAt,
    finishedAt: job.finishedAt
  })}\n\n`);
  for (const entry of job.logs) {
    res.write(`event: log\ndata: ${JSON.stringify(entry)}\n\n`);
  }
  job.clients.add(res);
  req.on('close', () => job.clients.delete(res));
});

app.get('/api/jobs/:jobId', (req, res) => {
  const job = jobs.get(req.params.jobId);
  if (!job) return res.status(404).json({ error: 'Job not found.' });
  res.json({
    jobId: job.id,
    status: job.status,
    exitCode: job.exitCode,
    startedAt: job.startedAt,
    finishedAt: job.finishedAt,
    processId: job.processId
  });
});

app.get('/api/next-index', (req, res) => {
  const subscriptionId = String(req.query.subscriptionId || '').trim();
  const prefix = String(req.query.prefix || '').trim();
  if (!subscriptionId) return res.status(400).json({ error: 'subscriptionId is required.' });
  if (!guidPattern.test(subscriptionId)) return res.status(400).json({ error: 'subscriptionId must be a GUID.' });
  if (!/^[a-z0-9]{1,8}$/.test(prefix)) return res.status(400).json({ error: 'prefix must be 1-8 lowercase alphanumeric characters.' });

  const az = spawn('az', [
    'group', 'list',
    '--subscription', subscriptionId,
    '--query', '[].name',
    '-o', 'json'
  ], azSpawnOptions);

  let stdout = '';
  let stderr = '';
  az.stdout.on('data', chunk => { stdout += chunk.toString(); });
  az.stderr.on('data', chunk => { stderr += chunk.toString(); });
  az.on('error', () => {
    if (!res.headersSent) res.json({ nextIndex: 1, highestIndex: 0, message: 'Azure CLI was not found; defaulting to 1.' });
  });
  az.on('close', code => {
    if (res.headersSent) return;
    if (code !== 0) {
      return res.json({ nextIndex: 1, highestIndex: 0, message: stderr.trim() || 'Could not list resource groups; defaulting to 1.' });
    }
    let names = [];
    try { names = JSON.parse(stdout || '[]'); } catch { names = []; }
    const re = new RegExp(`^rg-${prefix}-user(\\d+)$`);
    let highest = 0;
    for (const name of names) {
      const m = re.exec(name);
      if (m) highest = Math.max(highest, Number(m[1]));
    }
    res.json({ nextIndex: highest + 1, highestIndex: highest, message: '' });
  });
});

app.get('/api/subscriptions', (_req, res) => {
  const az = spawn('az', ['account', 'list', '--query', '[].{name:name,id:id}', '-o', 'json'], azSpawnOptions);
  let stdout = '';
  let stderr = '';
  az.stdout.on('data', chunk => { stdout += chunk.toString(); });
  az.stderr.on('data', chunk => { stderr += chunk.toString(); });
  az.on('error', () => {
    res.json({ subscriptions: [], message: 'Azure CLI was not found or could not be started.' });
  });
  az.on('close', code => {
    if (res.headersSent) return;
    if (code !== 0) {
      res.json({ subscriptions: [], message: 'Azure CLI is not logged in or could not list subscriptions.' });
      return;
    }
    try {
      res.json({ subscriptions: JSON.parse(stdout || '[]'), message: '' });
    } catch {
      res.json({ subscriptions: [], message: stderr || 'Could not parse Azure CLI subscription output.' });
    }
  });
});

app.use((err, _req, res, _next) => {
  res.status(500).json({ error: err.message || 'Unexpected server error.' });
});

app.listen(port, host, () => {
  console.log(`MicroHack SQL 2026 Lab Deployer listening at http://${host}:${port}`);
  if (appPassword) {
    console.log(`Auth: HTTP Basic enabled (user "${appUsername}").`);
  } else {
    console.log('Auth: DISABLED (no APP_PASSWORD). Bound to loopback only.');
  }
  console.log('Security: this tool runs deployments using the container/host az login. Run it only behind a trusted boundary.');
});
