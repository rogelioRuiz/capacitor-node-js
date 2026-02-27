# @choreruiz/capacitor-node-js

[![npm](https://img.shields.io/npm/v/@choreruiz/capacitor-node-js)](https://www.npmjs.com/package/@choreruiz/capacitor-node-js)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A full-fledged **Node.js v18 runtime** for [Capacitor](https://capacitorjs.com/) apps on iOS and Android.

This is a maintained fork of [Capacitor-NodeJS](https://github.com/hampoelz/Capacitor-NodeJS) by Rene Hampolz, with fixes for **Capacitor 8**, **Xcode 26**, and **Swift Package Manager** builds.

## What's different from upstream

- Capacitor 8.1 compatibility (removed deprecated `handleOnResume`/`handleOnPause` lifecycle methods)
- Xcode 26 explicit module builds (proper `import CapacitorNodejsBridge`)
- `builtin_modules` discovery in Capacitor's `public/` subdirectory
- SPM-first architecture (`ios/Bridge/` + `ios/Swift/` targets)
- CocoaPods support maintained via updated podspec
- Published to npm as `@choreruiz/capacitor-node-js` (no more manual `.tgz` installs)

## Install

```bash
npm install @choreruiz/capacitor-node-js
npx cap sync
```

After `cap sync`, copy the bridge modules into your iOS project:

```bash
cp -R node_modules/@choreruiz/capacitor-node-js/ios/assets/builtin_modules ios/App/App/public/builtin_modules
```

Or add this to your `package.json` scripts so it runs automatically:

```json
{
  "cap:sync": "cap sync && cp -R node_modules/@choreruiz/capacitor-node-js/ios/assets/builtin_modules ios/App/App/public/builtin_modules 2>/dev/null; true"
}
```

## Configuration

In `capacitor.config.ts`:

```typescript
plugins: {
  CapacitorNodeJS: {
    nodeDir: 'nodejs-project',     // directory inside public/ with your Node.js code
    startMode: 'auto',             // 'auto' or 'manual'
  },
}
```

## Usage

Place your Node.js project in `public/nodejs-project/` (or whatever `nodeDir` you configured). The engine starts automatically on app launch.

### Send messages to Node.js

```typescript
import { NodeJS } from '@choreruiz/capacitor-node-js';

await NodeJS.send({ eventName: 'myEvent', args: [{ hello: 'world' }] });
```

### Receive messages from Node.js

```typescript
import { NodeJS } from '@choreruiz/capacitor-node-js';

NodeJS.addListener('myResponse', (event) => {
  console.log('Got from Node:', event.args);
});
```

### Node.js side (bridge module)

```javascript
const { channel } = require('bridge');

channel.addListener('myEvent', (data) => {
  console.log('Got from Capacitor:', data);
  channel.send('myResponse', { result: 'ok' });
});

channel.send('ready');
```

## Architecture

```
+----------------------------------+
|          Capacitor App           |
|  (WebView / Vue / React / etc)   |
+----------------------------------+
|     CapacitorNodeJS Plugin       |
|   (Swift / Kotlin bridge)        |
+----------------------------------+
|     NodeMobile.xcframework       |
|   Node.js v18.20.4 (JIT-less)    |
+----------------------------------+
```

- **iOS**: Swift Package Manager with `CapacitorNodejsBridge` (C++17) and `CapacitorNodejsSwift` targets
- **Android**: Gradle with CMake NDK build (arm64-v8a, armeabi-v7a, x86_64)
- **Bridge**: IPC via JSON channels between Capacitor WebView and Node.js process

## Binary size

The npm package includes pre-built Node.js binaries:

| Platform | Architecture | Size |
|----------|-------------|------|
| iOS | arm64 (device) | 53 MB |
| iOS | arm64 + x86_64 (simulator) | 111 MB |
| Android | arm64-v8a | 60 MB |
| Android | armeabi-v7a | 109 MB |
| Android | x86_64 | 39 MB |

## Credits

Built on the excellent [Capacitor-NodeJS](https://github.com/hampoelz/Capacitor-NodeJS) by [Rene Hampolz](https://github.com/hampoelz). Node.js mobile binaries from [aspect-build/aspect-mobile](https://github.com/niceclaude/aspect-mobile).

## License

MIT - see [LICENSE](LICENSE)
