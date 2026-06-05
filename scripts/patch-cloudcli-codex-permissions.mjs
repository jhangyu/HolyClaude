import { readFileSync, writeFileSync } from 'fs';

const DEFAULT_CODEX_PATH = '/usr/local/lib/node_modules/@siteboon/claude-code-ui/server/openai-codex.js';
const cliTargetPath = process.argv[2];
const CODEX_PATH = cliTargetPath || DEFAULT_CODEX_PATH;
const ERROR_MESSAGE = '[patch] ERROR: CloudCLI Codex permission mode anchors not found';
const PATCH_MARKER = 'const HOLYCLAUDE_CODEX_CHAT_PERMISSION_PATCH = true;';
const ENV_NAME = 'HOLYCLAUDE_CODEX_CHAT_PERMISSION_MODE';
const ENV_CONSTANT = 'HOLYCLAUDE_CODEX_CHAT_PERMISSION_MODE_ENV';
const MAP_ANCHOR = 'function mapPermissionModeToCodexOptions(permissionMode)';
const QUERY_ANCHOR = 'export async function queryCodex(command, options = {}, ws)';
const DESTRUCTURING_ANCHOR = "permissionMode = 'default'";
const DESTRUCTURING_NEEDLE = "    permissionMode = 'default'\n  } = options;";
const DESTRUCTURING_REPLACEMENT = "    permissionMode\n  } = options;";
const WORKING_DIRECTORY_ANCHOR = '  const workingDirectory = cwd || projectPath || process.cwd();';
const MAP_CALL_ANCHOR = 'const { sandboxMode, approvalPolicy } = mapPermissionModeToCodexOptions(permissionMode);';
const MAP_CALL_REPLACEMENT = 'const { sandboxMode, approvalPolicy } = mapPermissionModeToCodexOptions(effectivePermissionMode);';

const helperCode = `
const HOLYCLAUDE_CODEX_CHAT_PERMISSION_PATCH = true;
const HOLYCLAUDE_CODEX_CHAT_PERMISSION_MODE_ENV = 'HOLYCLAUDE_CODEX_CHAT_PERMISSION_MODE';
const HOLYCLAUDE_CODEX_CHAT_PERMISSION_MODES = new Set(['default', 'acceptEdits', 'bypassPermissions']);

function getConfiguredCodexChatPermissionMode() {
  const configuredPermissionMode = process.env[HOLYCLAUDE_CODEX_CHAT_PERMISSION_MODE_ENV];
  if (configuredPermissionMode == null || String(configuredPermissionMode).trim() === '') {
    return 'acceptEdits';
  }

  const normalizedPermissionMode = String(configuredPermissionMode).trim();
  if (HOLYCLAUDE_CODEX_CHAT_PERMISSION_MODES.has(normalizedPermissionMode)) {
    return normalizedPermissionMode;
  }

  console.warn(\`[Codex] Invalid \${HOLYCLAUDE_CODEX_CHAT_PERMISSION_MODE_ENV}; falling back to default\`);
  return 'default';
}

function resolveCodexChatPermissionMode(permissionMode, hasExplicitPermissionMode) {
  if (!hasExplicitPermissionMode) {
    return getConfiguredCodexChatPermissionMode();
  }

  const normalizedPermissionMode = String(permissionMode).trim();
  if (HOLYCLAUDE_CODEX_CHAT_PERMISSION_MODES.has(normalizedPermissionMode)) {
    return normalizedPermissionMode;
  }

  console.warn('[Codex] Invalid request permission mode; falling back to default');
  return 'default';
}
`;

function hasHolyClaudeBackport(source) {
  return source.includes(PATCH_MARKER)
    && source.includes(`const ${ENV_CONSTANT} = '${ENV_NAME}';`)
    && source.includes("const HOLYCLAUDE_CODEX_CHAT_PERMISSION_MODES = new Set(['default', 'acceptEdits', 'bypassPermissions']);")
    && source.includes('function getConfiguredCodexChatPermissionMode()')
    && source.includes('function resolveCodexChatPermissionMode(permissionMode, hasExplicitPermissionMode)')
    && source.includes("hasOwnProperty.call(options, 'permissionMode')")
    && source.includes(MAP_CALL_REPLACEMENT);
}

function hasFullHolyClaudeRuntimeContract(source) {
  const envAccessPatterns = [
    `process.env.${ENV_NAME}`,
    `process.env['${ENV_NAME}']`,
    `process.env["${ENV_NAME}"]`,
    `process.env[${ENV_CONSTANT}]`
  ];
  const explicitRequestPatterns = [
    "hasOwnProperty.call(options, 'permissionMode')",
    'hasOwnProperty.call(options, "permissionMode")',
    "Object.hasOwn(options, 'permissionMode')",
    'Object.hasOwn(options, "permissionMode")'
  ];
  const hasEnvFallback = envAccessPatterns.some((pattern) => source.includes(pattern));
  const hasExplicitRequestCheck = explicitRequestPatterns.some((pattern) => source.includes(pattern));
  const hasAllowedModes = ["'default'", "'acceptEdits'", "'bypassPermissions'"].every((mode) => source.includes(mode));
  const hasSafeDefaultBehavior = /return\s+['"]acceptEdits['"]/.test(source)
    && /falling back to default/.test(source)
    && /return\s+['"]default['"]/.test(source);
  const hasCodexMappings = source.includes("sandboxMode: 'workspace-write'")
    && source.includes("sandboxMode: 'danger-full-access'")
    && source.includes("approvalPolicy: 'never'")
    && source.includes("approvalPolicy: 'untrusted'");
  const hasResolvedMapCall = !source.includes(MAP_CALL_ANCHOR)
    && /mapPermissionModeToCodexOptions\(\s*(?:effective|resolved)\w*PermissionMode\s*\)/.test(source);

  return hasEnvFallback
    && hasExplicitRequestCheck
    && hasAllowedModes
    && hasSafeDefaultBehavior
    && hasCodexMappings
    && hasResolvedMapCall;
}

function findFunctionEnd(source, functionAnchor) {
  const functionIndex = source.indexOf(functionAnchor);
  if (functionIndex === -1) {
    return -1;
  }

  const bodyStartIndex = source.indexOf('{', functionIndex);
  if (bodyStartIndex === -1) {
    return -1;
  }

  let braceDepth = 0;
  for (let sourceIndex = bodyStartIndex; sourceIndex < source.length; sourceIndex += 1) {
    const character = source[sourceIndex];
    if (character === '{') {
      braceDepth += 1;
    } else if (character === '}') {
      braceDepth -= 1;
      if (braceDepth === 0) {
        return sourceIndex + 1;
      }
    }
  }

  return -1;
}

function readCodexSource() {
  try {
    return readFileSync(CODEX_PATH, 'utf8');
  } catch (error) {
    if (!cliTargetPath) {
      throw error;
    }
    console.error(ERROR_MESSAGE);
    process.exit(1);
  }
}

function writeCodexSource(source) {
  try {
    writeFileSync(CODEX_PATH, source);
  } catch (error) {
    if (!cliTargetPath) {
      throw error;
    }
    console.error(ERROR_MESSAGE);
    process.exit(1);
  }
}

let source = readCodexSource();

if (hasHolyClaudeBackport(source)) {
  console.log('[patch] CloudCLI Codex permission mode already applied');
  process.exit(0);
}

if (hasFullHolyClaudeRuntimeContract(source)) {
  console.log('[patch] CloudCLI Codex permission mode already supported upstream');
  process.exit(0);
}

const requiredAnchorsPresent = source.includes(MAP_ANCHOR)
  && source.includes(QUERY_ANCHOR)
  && source.includes(DESTRUCTURING_ANCHOR)
  && source.includes(DESTRUCTURING_NEEDLE)
  && source.includes(WORKING_DIRECTORY_ANCHOR)
  && source.includes(MAP_CALL_ANCHOR);
const mapFunctionEndIndex = findFunctionEnd(source, MAP_ANCHOR);

if (!requiredAnchorsPresent || mapFunctionEndIndex === -1) {
  console.error(ERROR_MESSAGE);
  process.exit(1);
}

source = `${source.slice(0, mapFunctionEndIndex)}${helperCode}${source.slice(mapFunctionEndIndex)}`;
source = source.replace(DESTRUCTURING_NEEDLE, DESTRUCTURING_REPLACEMENT);
source = source.replace(
  WORKING_DIRECTORY_ANCHOR,
  "  const hasExplicitPermissionMode = Object.prototype.hasOwnProperty.call(options, 'permissionMode');\n  const effectivePermissionMode = resolveCodexChatPermissionMode(permissionMode, hasExplicitPermissionMode);\n  const workingDirectory = cwd || projectPath || process.cwd();"
);
source = source.replace(MAP_CALL_ANCHOR, MAP_CALL_REPLACEMENT);

writeCodexSource(source);
console.log('[patch] CloudCLI Codex permission mode applied');
