/**
 * اسکریپت بیلد سبک همکار هاب
 * ------------------------------------------------------------
 * این اسکریپت به‌جای Vite/Rolldown و Tailwind v4 (که به باینری‌های
 * نیتیو نیاز دارند و روی CPUهای قدیمی مثل AMD Phenom خطای
 * «Illegal instruction» می‌دهند) از ابزارهای کاملاً سازگار استفاده می‌کند:
 *
 *   - esbuild   : باندلر نوشته‌شده با Go (هدف GOAMD64=v1، سازگار با x86-64 پایه)
 *   - Tailwind  : نسخه ۳ که کاملاً جاوااسکریپت خالص است (بدون oxide/Rust)
 *
 * خروجی نهایی در پوشه dist/ قرار می‌گیرد و سرور با `node server.js`
 * اجرا می‌شود. همه‌چیز (فونت، استایل، اسکریپت) محلی و آفلاین است.
 */
import { build, context } from 'esbuild';
import { promises as fs } from 'fs';
import fsSync from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import postcss from 'postcss';
import tailwindcss from 'tailwindcss';
import autoprefixer from 'autoprefixer';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, '..');
const dist = path.join(root, 'dist');
const watchMode = process.argv.includes('--watch');

// استاب کردن ایمپورت‌های CSS در جاوااسکریپت (CSS جداگانه با PostCSS ساخته می‌شود)
const cssStubPlugin = {
  name: 'css-stub',
  setup(buildApi) {
    buildApi.onResolve({ filter: /\.css$/ }, (args) => ({
      path: args.path,
      namespace: 'css-stub',
    }));
    buildApi.onLoad({ filter: /.*/, namespace: 'css-stub' }, () => ({
      contents: '',
      loader: 'js',
    }));
  },
};

async function ensureDir(dir) {
  await fs.mkdir(dir, { recursive: true });
}

// پاک‌سازی امن پوشه dist؛ برخی پوشه‌ها (مثل OneDrive) ممکن است موقتاً قفل یا read-only باشند.
async function cleanDir(dir) {
  await fs.chmod(dir, 0o777).catch(() => {});
  try {
    await fs.rm(dir, { recursive: true, force: true, maxRetries: 4, retryDelay: 100 });
    return true;
  } catch {
    return false;
  }
}

async function copyFile(src, dest) {
  await ensureDir(path.dirname(dest));
  await fs.copyFile(src, dest);
}

async function copyDirContents(src, dest, filter = () => true) {
  if (!fsSync.existsSync(src)) return 0;
  await ensureDir(dest);
  let count = 0;
  for (const name of await fs.readdir(src)) {
    const s = path.join(src, name);
    const d = path.join(dest, name);
    const stat = await fs.stat(s);
    if (stat.isDirectory()) {
      count += await copyDirContents(s, d, filter);
    } else if (filter(name)) {
      await copyFile(s, d);
      count++;
    }
  }
  return count;
}

async function buildCss() {
  const cssEntry = path.join(root, 'src', 'index.css');
  const css = await fs.readFile(cssEntry, 'utf8');
  const result = await postcss([
    tailwindcss({ config: path.join(root, 'tailwind.config.js') }),
    autoprefixer(),
  ]).process(css, { from: cssEntry, to: path.join(dist, 'assets', 'app.css') });
  await ensureDir(path.join(dist, 'assets'));
  await fs.writeFile(path.join(dist, 'assets', 'app.css'), result.css);
  const kb = (Buffer.byteLength(result.css) / 1024).toFixed(1);
  console.log(`  ✓ CSS ساخته شد (${kb} KB)`);
}

async function copyStatic() {
  await copyFile(path.join(root, 'index.html'), path.join(dist, 'index.html'));
  const images = await copyDirContents(
    path.join(root, 'src', 'assets', 'images'),
    path.join(dist, 'assets', 'images'),
    (n) => /\.(jpe?g|png|webp|gif|svg|avif)$/i.test(n)
  );
  const fonts = await copyDirContents(
    path.join(root, 'assets', 'fonts'),
    path.join(dist, 'assets', 'fonts'),
    (n) => /\.(woff2?|ttf|otf)$/i.test(n)
  );
  console.log(`  ✓ فایل‌های ثابت کپی شدند (${images} تصویر، ${fonts} فونت)`);
}

const clientOptions = {
  entryPoints: [path.join(root, 'src', 'main.tsx')],
  bundle: true,
  format: 'esm',
  platform: 'browser',
  target: ['es2020'],
  jsx: 'automatic',
  minify: true,
  sourcemap: false,
  legalComments: 'none',
  outfile: path.join(dist, 'assets', 'app.js'),
  define: { 'process.env.NODE_ENV': '"production"' },
  plugins: [cssStubPlugin],
  logLevel: 'warning',
};

const serverOptions = {
  entryPoints: [path.join(root, 'server.ts')],
  bundle: true,
  format: 'esm',
  platform: 'node',
  target: ['node16'],
  minify: false,
  sourcemap: false,
  legalComments: 'none',
  outfile: path.join(root, 'server.js'),
  banner: {
    js: "import { createRequire as __createRequire } from 'module';const require = __createRequire(import.meta.url);",
  },
  logLevel: 'warning',
};

async function bundleClient() {
  await build(clientOptions);
  const stat = await fs.stat(clientOptions.outfile);
  console.log(`  ✓ باندل کلاینت ساخته شد (${(stat.size / 1024).toFixed(1)} KB)`);
}

async function bundleServer() {
  await build(serverOptions);
  const stat = await fs.stat(serverOptions.outfile);
  console.log(`  ✓ سرور باندل شد → server.js (${(stat.size / 1024).toFixed(1)} KB)`);
}

async function runOnce() {
  console.log('🔨 در حال ساخت همکار هاب (نسخه سبک و سازگار با CPU قدیمی)...');
  // اگر پوشه dist قابل حذف نبود (قفل OneDrive)، فایل‌ها را بازنویسی می‌کنیم.
  const cleaned = await cleanDir(dist);
  if (!cleaned) console.log('  ℹ️ پوشه dist قفل بود؛ فایل‌ها در همان محل بازنویسی می‌شوند.');
  await ensureDir(path.join(dist, 'assets'));
  await copyStatic();
  await buildCss();
  await bundleClient();
  await bundleServer();
  console.log('✅ بیلد کامل شد. برای اجرا:  npm start');
}

async function runWatch() {
  await runOnce();
  console.log('👀 حالت watch فعال شد...');
  const clientCtx = await context(clientOptions);
  await clientCtx.watch();
  const serverCtx = await context(serverOptions);
  await serverCtx.watch();

  let timer = null;
  const onChange = () => {
    clearTimeout(timer);
    timer = setTimeout(async () => {
      try {
        await copyStatic();
        await buildCss();
      } catch (e) {
        console.error('خطا در بیلد مجدد:', e.message);
      }
    }, 150);
  };
  fsSync.watch(path.join(root, 'src'), { recursive: true }, onChange);
  fsSync.watch(path.join(root, 'index.html'), onChange);
  fsSync.watch(path.join(root, 'assets'), { recursive: true }, onChange);
}

(watchMode ? runWatch() : runOnce()).catch((err) => {
  console.error('❌ خطا در بیلد:', err);
  process.exit(1);
});
