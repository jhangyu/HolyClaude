import { readFileSync, writeFileSync } from 'fs';

const ORCHESTRATOR_PATH = '/usr/local/lib/node_modules/@siteboon/claude-code-ui/server/services/notification-orchestrator.js';
const ERROR_MESSAGE = '[patch] ERROR: CloudCLI notification orchestrator anchors not found';
const IMPORT_ANCHOR = "import { notificationPreferencesDb, pushSubscriptionsDb, sessionNamesDb } from '../database/db.js';";
const SPAWN_IMPORT = "import { spawn } from 'child_process';";
const STOP_ANCHOR = "function notifyRunStopped({ userId, provider, sessionId = null, stopReason = 'completed', sessionName = null })";
const FAILED_ANCHOR = "function notifyRunFailed({ userId, provider, sessionId = null, error, sessionName = null })";
const HELPER_MARKER = "const APPRISE_PROVIDER_ALLOWLIST = new Set(['codex']);";
const LEGACY_HELPER_NAME = 'notifyAppriseLifecycle';
const HELPER_NAME = 'sendAppriseLifecycleNotification';
const SANITIZE_MARKER = "replace(/\\x00/g, '').replace(/\\s+/g, ' ')";

const helperCode = `
const APPRISE_PROVIDER_ALLOWLIST = new Set(['codex']);

function sanitizeAppriseArg(value, maxLength) {
  if (value == null) {
    return null;
  }

  const sanitized = String(value).replace(/\\x00/g, '').replace(/\\s+/g, ' ').trim();
  if (!sanitized) {
    return null;
  }

  return sanitized.length > maxLength ? sanitized.slice(0, maxLength) : sanitized;
}

function sendAppriseLifecycleNotification({ provider, kind, sessionId = null, sessionName = null, stopReason = null, error = null }) {
  if (!APPRISE_PROVIDER_ALLOWLIST.has(provider)) {
    return;
  }

  const args = [kind, '--provider', provider];
  const cleanSessionId = sanitizeAppriseArg(sessionId, 80);
  const cleanSessionName = sanitizeAppriseArg(sessionName, 80);
  const cleanStopReason = sanitizeAppriseArg(stopReason, 120);
  const cleanError = sanitizeAppriseArg(error, 180);

  if (cleanSessionId) {
    args.push('--session-id', cleanSessionId);
  }
  if (cleanSessionName) {
    args.push('--session-name', cleanSessionName);
  }
  if (cleanStopReason) {
    args.push('--reason', cleanStopReason);
  }
  if (cleanError) {
    args.push('--error', cleanError);
  }

  try {
    const child = spawn('/usr/local/bin/notify.py', args, {
      shell: false,
      detached: true,
      stdio: 'ignore',
      env: process.env
    });
    child.on('error', () => {});
    if (typeof child.unref === 'function') child.unref();
  } catch {
  }
}
`;

const stopCall = `  sendAppriseLifecycleNotification({
    provider,
    kind: 'stop',
    sessionId,
    sessionName,
    stopReason
  });

`;

const failedCall = `  const errorMessage = normalizeErrorMessage(error);

  sendAppriseLifecycleNotification({
    provider,
    kind: 'error',
    sessionId,
    sessionName,
    error: errorMessage
  });`;

let source = readFileSync(ORCHESTRATOR_PATH, 'utf8');

const requiredAnchorsPresent = source.includes(STOP_ANCHOR) && source.includes(FAILED_ANCHOR) && source.includes(IMPORT_ANCHOR);
if (!requiredAnchorsPresent) {
  console.error(ERROR_MESSAGE);
  process.exit(1);
}

const alreadyApplied = source.includes(SPAWN_IMPORT)
  && source.includes(HELPER_MARKER)
  && source.includes(`function ${HELPER_NAME}(`)
  && source.includes(SANITIZE_MARKER)
  && source.includes("child.on('error', () => {})")
  && source.includes('typeof child.unref')
  && source.includes("kind: 'stop'")
  && source.includes("kind: 'error'");

if (alreadyApplied) {
  console.log('[patch] CloudCLI Apprise lifecycle notifications already applied');
  process.exit(0);
}

if (!source.includes(SPAWN_IMPORT)) {
  source = source.replace(IMPORT_ANCHOR, `${IMPORT_ANCHOR}\n${SPAWN_IMPORT}`);
}

if (source.includes(LEGACY_HELPER_NAME)) {
  source = source.replaceAll(LEGACY_HELPER_NAME, HELPER_NAME);
}

if (source.includes('    child.unref();')) {
  source = source.replaceAll(
    '    child.unref();',
    "    child.on('error', () => {});\n    if (typeof child.unref === 'function') child.unref();"
  );
}

const legacyCatchBlock = '  } catch (error) {\n'
  + "    console." + "error('[patch] CloudCLI Apprise lifecycle notification "
  + "spawn failed:', error?.message || error);\n"
  + '  }';
if (source.includes(legacyCatchBlock)) {
  source = source.replace(legacyCatchBlock, '  } catch {\n  }');
}

if (!source.includes(HELPER_MARKER)) {
  source = source.replace(`${STOP_ANCHOR} {`, `${helperCode}\n${STOP_ANCHOR} {`);
}

if (!source.includes(stopCall)) {
  source = source.replace(`${STOP_ANCHOR} {\n`, `${STOP_ANCHOR} {\n${stopCall}`);
}

const failedNeedle = `${FAILED_ANCHOR} {\n  const errorMessage = normalizeErrorMessage(error);`;
if (!source.includes(failedCall)) {
  if (!source.includes(failedNeedle)) {
    console.error(ERROR_MESSAGE);
    process.exit(1);
  }
  source = source.replace(failedNeedle, `${FAILED_ANCHOR} {\n${failedCall}`);
}

writeFileSync(ORCHESTRATOR_PATH, source);
console.log('[patch] CloudCLI Apprise lifecycle notifications applied');
