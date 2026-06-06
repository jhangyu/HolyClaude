import { readFileSync, writeFileSync } from 'fs';

const cliTargetPath = process.argv[2];
const ERROR_MESSAGE = '[patch] ERROR: CloudCLI shell scroll anchor not found';

if (!cliTargetPath) {
  console.error(ERROR_MESSAGE);
  process.exit(1);
}

let source;
try {
  source = readFileSync(cliTargetPath, 'utf8');
} catch {
  console.error(ERROR_MESSAGE);
  process.exit(1);
}

if (source.includes('scrollToLine(_vp)')) {
  console.log('[patch] CloudCLI shell scroll position fix already applied');
  process.exit(0);
}

const focusOnlyHandlerPattern = /const ([A-Za-z_$][A-Za-z0-9_$]*)=\(\)=>\{([A-Za-z_$][A-Za-z0-9_$]*)\.current\?\.focus\(\)\}/;
const match = source.match(focusOnlyHandlerPattern);
if (!match) {
  console.error(ERROR_MESSAGE);
  process.exit(1);
}

const [, functionName, terminalRef] = match;
const replacement = `const ${functionName}=()=>{const _vp=${terminalRef}.current?.buffer?.active?.viewportY??0;${terminalRef}.current?.focus();${terminalRef}.current?.scrollToLine(_vp)}`;

source = source.replace(focusOnlyHandlerPattern, replacement);

if (!source.includes('scrollToLine(_vp)')) {
  console.error(ERROR_MESSAGE);
  process.exit(1);
}

writeFileSync(cliTargetPath, source);
console.log('[patch] CloudCLI shell scroll position fix applied');
