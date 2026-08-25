const {defineConfig, devices} = require('@playwright/test');

const executablePath = process.env.PLAYWRIGHT_EXECUTABLE_PATH;

module.exports = defineConfig({
  testDir: './tests/browser',
  globalSetup: require.resolve('./tests/browser/emulator.setup.cjs'),
  timeout: 90_000,
  expect: {timeout: 20_000},
  fullyParallel: false,
  workers: 1,
  reporter: [['list'], ['html', {open: 'never', outputFolder: 'qa/playwright-report'}]],
  use: {
    baseURL: 'http://127.0.0.1:7357',
    ...(executablePath ? {launchOptions: {executablePath}} : {}),
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'off',
  },
  webServer: {
    command:
      'flutter build web --release --dart-define=USE_FIREBASE_EMULATOR=true --dart-define=BROWSER_QA=true --output=build/web-browser && bash tooling/prepare_web_artifact.sh build/web-browser && WEB_ROOT=build/web-browser node tests/browser/spa-server.cjs',
    url: 'http://127.0.0.1:7357/aidsuhis',
    reuseExistingServer: process.env.PLAYWRIGHT_REUSE_SERVER === 'true',
    timeout: 240_000,
  },
  projects: [
    {
      name: 'desktop-chromium',
      use: {...devices['Desktop Chrome'], viewport: {width: 1440, height: 1000}},
    },
    {
      name: 'tablet-chromium',
      use: {...devices['Desktop Chrome'], viewport: {width: 900, height: 1100}},
    },
    {
      name: 'mobile-chromium',
      use: {...devices['Desktop Chrome'], viewport: {width: 390, height: 844}},
    },
  ],
});
