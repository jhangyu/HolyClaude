import { readFileSync, writeFileSync } from 'fs';

const DEFAULT_ORCHESTRATOR_PATH = '/usr/local/lib/node_modules/@cloudcli-ai/cloudcli/dist-server/server/services/notification-orchestrator.js';
const cliTargetPath = process.argv[2];
const ORCHESTRATOR_PATH = cliTargetPath || DEFAULT_ORCHESTRATOR_PATH;
const ERROR_MESSAGE = '[patch] ERROR: CloudCLI notification orchestrator anchors not found';
const IMPORT_ANCHORS = [
  "import { notificationPreferencesDb, pushSubscriptionsDb, sessionsDb } from '../modules/database/index.js';",
  "import { notificationPreferencesDb, pushSubscriptionsDb, sessionNamesDb } from '../database/db.js';"
];
const SPAWN_IMPORT = "import { spawn } from 'child_process';";
const STOP_ANCHOR = "function notifyRunStopped(";
const FAILED_ANCHOR = "function notifyRunFailed(";
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

function readOrchestratorSource() {
  try {
    return readFileSync(ORCHESTRATOR_PATH, 'utf8');
  } catch (error) {
    if (!cliTargetPath) {
      throw error;
    }
    console.error(ERROR_MESSAGE);
    process.exit(1);
  }
}

function writeOrchestratorSource(source) {
  try {
    writeFileSync(ORCHESTRATOR_PATH, source);
  } catch (error) {
    if (!cliTargetPath) {
      throw error;
    }
    console.error(ERROR_MESSAGE);
    process.exit(1);
  }
}

let source = readOrchestratorSource();
const importAnchor = IMPORT_ANCHORS.find((anchor) => source.includes(anchor));

const requiredAnchorsPresent = source.includes(STOP_ANCHOR) && source.includes(FAILED_ANCHOR) && importAnchor;
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
  source = source.replace(importAnchor, `${importAnchor}\n${SPAWN_IMPORT}`);
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

function findFunctionBodyStart(source, functionAnchor) {
  const functionIndex = source.indexOf(functionAnchor);
  if (functionIndex === -1) {
    return -1;
  }

  const paramsStartIndex = source.indexOf('(', functionIndex);
  if (paramsStartIndex === -1) {
    return -1;
  }

  let parenDepth = 0;
  for (let sourceIndex = paramsStartIndex; sourceIndex < source.length; sourceIndex += 1) {
    const character = source[sourceIndex];
    if (character === '(') {
      parenDepth += 1;
    } else if (character === ')') {
      parenDepth -= 1;
      if (parenDepth === 0) {
        return source.indexOf('{', sourceIndex);
      }
    }
  }

  return -1;
}

function insertAfterFunctionOpen(source, functionAnchor, insertText) {
  const bodyStartIndex = findFunctionBodyStart(source, functionAnchor);
  if (bodyStartIndex === -1) {
    return null;
  }

  return `${source.slice(0, bodyStartIndex + 1)}\n${insertText}${source.slice(bodyStartIndex + 1)}`;
}

if (!source.includes(HELPER_MARKER)) {
  const stopFunctionIndex = source.indexOf(STOP_ANCHOR);
  if (stopFunctionIndex === -1) {
    console.error(ERROR_MESSAGE);
    process.exit(1);
  }
  source = `${source.slice(0, stopFunctionIndex)}${helperCode}\n${source.slice(stopFunctionIndex)}`;
}

if (!source.includes(stopCall)) {
  const nextSource = insertAfterFunctionOpen(source, STOP_ANCHOR, stopCall);
  if (nextSource == null) {
    console.error(ERROR_MESSAGE);
    process.exit(1);
  }
  source = nextSource;
}

if (!source.includes(failedCall)) {
  const failedBodyStartIndex = findFunctionBodyStart(source, FAILED_ANCHOR);
  if (failedBodyStartIndex === -1) {
    console.error(ERROR_MESSAGE);
    process.exit(1);
  }
  const existingErrorMessageIndex = source.indexOf('  const errorMessage = normalizeErrorMessage(error);', failedBodyStartIndex);
  if (existingErrorMessageIndex === -1) {
    console.error(ERROR_MESSAGE);
    process.exit(1);
  }
  const existingErrorMessageEndIndex = existingErrorMessageIndex + '  const errorMessage = normalizeErrorMessage(error);'.length;
  source = `${source.slice(0, existingErrorMessageIndex)}${failedCall}${source.slice(existingErrorMessageEndIndex)}`;
}

writeOrchestratorSource(source);
console.log('[patch] CloudCLI Apprise lifecycle notifications applied');
