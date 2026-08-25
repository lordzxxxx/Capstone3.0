const {test, expect} = require('@playwright/test');

const identities = () => JSON.parse(process.env.BROWSER_TEST_IDENTITIES || '{}');

const bhwRoutes = [
  ['/bhw/dashboard', /Barangay Health Operations/i],
  ['/bhw/patients', /Patient Records/i],
  ['/bhw/checkups', /Check-up Management/i],
  ['/bhw/prenatal', /Prenatal Care/i],
  ['/bhw/immunization', /Immunization Management/i],
  ['/bhw/communicable', /Communicable Disease Management/i],
  ['/bhw/non-communicable', /Non-Communicable Disease Management/i],
  ['/bhw/morbidity', /Morbidity Records/i],
  ['/bhw/mortality', /Mortality Monitoring/i],
  ['/bhw/referrals', /Referral Records/i],
  ['/bhw/summary', /Health Summary|Summary/i],
  ['/bhw/analytics', /Analytics/i],
  ['/bhw/profile', /User Details|Profile/i],
];

const choRoutes = [
  ['/cho/dashboard', /City Health Operations|CHO Dashboard/i],
  ['/cho/patients', /Patient/i],
  ['/cho/checkups', /Check-up/i],
  ['/cho/prenatal', /Prenatal/i],
  ['/cho/immunization', /Immunization/i],
  ['/cho/morbidity', /Morbidity/i],
  ['/cho/mortality', /Mortality/i],
  ['/cho/referrals', /Referral/i],
  ['/cho/bhw-management', /BHW/i],
  ['/cho/reports', /Analytics|Report/i],
  ['/cho/announcements', /Announcement/i],
  ['/cho/data-quality', /Data Quality/i],
  ['/cho/audit-logs', /Audit/i],
  ['/cho/notifications', /Notification/i],
  ['/cho/profile', /Profile/i],
];

async function enableFlutterSemantics(page) {
  const placeholder = page.locator('flt-semantics-placeholder');
  if (await placeholder.count()) {
    await placeholder.evaluate((element) => element.click());
  }
  await page
    .locator('flt-semantics-placeholder')
    .waitFor({state: 'detached', timeout: 30_000})
    .catch(() => {});
}

async function openFlutterRoute(page, route) {
  await page.goto(route, {waitUntil: 'domcontentloaded'});
  await page.locator('flutter-view').waitFor({state: 'attached', timeout: 120_000});
  await enableFlutterSemantics(page);
}

async function expectFlutterText(page, text) {
  await expect(
    page.locator('flt-semantics-host').getByText(text).first(),
  ).toBeVisible({timeout: 30_000});
}

async function login(page, identity) {
  await openFlutterRoute(page, '/login');
  await expectFlutterText(page, /Welcome back/i);

  const emailField = page.getByRole('textbox', {name: /you@example.com|email/i}).first();
  await emailField.click();
  await page.keyboard.type(identity.email);

  const passwordField = page.getByRole('textbox', {
    name: /enter your password|password/i,
  }).first();
  await passwordField.click();
  await page.keyboard.type(identity.password);
  await page.getByRole('button', {name: /^Sign in$/i}).click();

  await expectFlutterText(page, /Login successful/i);
  await page.getByRole('button', {name: /Dashboard|Referral Center|Super Admin Center/i}).click();
  await page.waitForURL(identity.expectedRoute || '**/*', {timeout: 30_000});
  await enableFlutterSemantics(page);
}

async function signOutToIsolatedContext(browser, project, identity) {
  const context = await browser.newContext({viewport: project.use.viewport});
  const page = await context.newPage();
  await login(page, identity);
  return {context, page};
}

test.describe('public, deep-link, and responsive shell', () => {
  test('public and unknown routes render without console failures', async ({page}, testInfo) => {
    const runtimeErrors = [];
    page.on('pageerror', (error) => runtimeErrors.push(error.message));

    for (const [route, heading] of [
      ['/aidsuhis', /AI-DSUHIS/i],
      ['/', /AI-DSUHIS/i],
      ['/login', /Welcome back/i],
      ['/bhw/login', /BHW Portal Login/i],
      ['/cho/login', /CHO Portal Login/i],
      ['/signup', /Create|Register/i],
      ['/forgot-password', /Forgot|Reset/i],
      ['/not-a-real-route', /Page not found|not found/i],
    ]) {
      await openFlutterRoute(page, route);
      await expectFlutterText(page, heading);
    }

    const hasHorizontalOverflow = await page.evaluate(
      () => document.documentElement.scrollWidth > document.documentElement.clientWidth + 1,
    );
    expect(hasHorizontalOverflow).toBe(false);
    expect(runtimeErrors, `runtime errors in ${testInfo.project.name}`).toEqual([]);
  });

  test('anonymous protected deep links redirect to login', async ({page}) => {
    for (const route of ['/bhw/patients?view=records', '/cho/reports', '/doctor/referrals']) {
      await openFlutterRoute(page, route);
      await expect(page).toHaveURL(/\/login$/);
      await expectFlutterText(page, /Welcome back/i);
    }
  });
});

test.describe('role routes and permissions', () => {
  test('BHW canonical and legacy routes stay BHW-scoped', async ({browser}, testInfo) => {
    const identity = {...identities().bhw, expectedRoute: '**/bhw/dashboard'};
    const {context, page} = await signOutToIsolatedContext(browser, testInfo.project, identity);
    for (const [route, heading] of bhwRoutes) {
      await openFlutterRoute(page, route);
      await expectFlutterText(page, heading);
      await expect(page.getByText(/Workspace unavailable/i)).toHaveCount(0);
    }
    for (const [legacy, canonical] of [
      ['/checkups?view=records', '/bhw/checkups?view=records'],
      ['/prenatal', '/bhw/prenatal'],
      ['/morbidity', '/bhw/morbidity'],
      ['/mortality', '/bhw/mortality'],
      ['/CommunicablePage', '/bhw/communicable'],
      ['/NonCommunicablePage', '/bhw/non-communicable'],
      ['/ReferralsPage', '/bhw/referrals'],
      ['/bhw-profile', '/bhw/profile'],
    ]) {
      await openFlutterRoute(page, legacy);
      await expect(page).toHaveURL(new RegExp(`${canonical.replace(/[?]/g, '\\?')}$`));
    }
    await openFlutterRoute(page, '/cho/dashboard');
    await expectFlutterText(page, /Workspace unavailable/i);
    await context.close();
  });

  test('CHO routes work but governance routes remain admin-only', async ({browser}, testInfo) => {
    const identity = {...identities().cho, expectedRoute: '**/cho/dashboard'};
    const {context, page} = await signOutToIsolatedContext(browser, testInfo.project, identity);
    for (const [route, heading] of choRoutes) {
      await openFlutterRoute(page, route);
      await expectFlutterText(page, heading);
      await expect(page.getByText(/Workspace unavailable/i)).toHaveCount(0);
    }
    for (const [legacy, canonical] of [
      ['/cho/bhwManagement', '/cho/bhw-management'],
      ['/cho/dataQuality', '/cho/data-quality'],
      ['/cho/auditLogs', '/cho/audit-logs'],
    ]) {
      await openFlutterRoute(page, legacy);
      await expect(page).toHaveURL(new RegExp(`${canonical}$`));
    }
    await openFlutterRoute(page, '/cho/super-admin');
    await expectFlutterText(page, /Workspace unavailable/i);
    await context.close();
  });

  test('doctor is limited to assigned referral workflow', async ({browser}, testInfo) => {
    const identity = {...identities().doctor, expectedRoute: '**/doctor/referrals'};
    const {context, page} = await signOutToIsolatedContext(browser, testInfo.project, identity);
    await expectFlutterText(page, /Referral/i);
    await openFlutterRoute(page, '/bhw/dashboard');
    await expectFlutterText(page, /Workspace unavailable/i);
    await openFlutterRoute(page, '/cho/dashboard');
    await expectFlutterText(page, /Workspace unavailable/i);
    await context.close();
  });

  test('super-admin can use CHO and governance routes but not BHW pages', async ({browser}, testInfo) => {
    const identity = {...identities().superAdmin, expectedRoute: '**/cho/super-admin'};
    const {context, page} = await signOutToIsolatedContext(browser, testInfo.project, identity);
    await expectFlutterText(page, /User Governance|Super Admin/i);
    for (const route of ['/cho/dashboard', '/cho/role-manager', '/cho/super-admin']) {
      await openFlutterRoute(page, route);
      await expect(page.getByText(/Workspace unavailable/i)).toHaveCount(0);
    }
    await openFlutterRoute(page, '/bhw/patients');
    await expectFlutterText(page, /Workspace unavailable/i);
    await context.close();
  });
});

test.describe('critical controls and connection feedback', () => {
  test('BHW patient search, view switch, add action, and offline banner remain usable', async ({browser}, testInfo) => {
    const identity = {...identities().bhw, expectedRoute: '**/bhw/dashboard'};
    const {context, page} = await signOutToIsolatedContext(browser, testInfo.project, identity);
    await openFlutterRoute(page, '/bhw/patients?view=records');
    await expectFlutterText(page, /Patient Records/i);
    await expectFlutterText(page, /Search by name/i);
    await expect(page.getByRole('button', {name: /Add New Patient/i})).toBeVisible();

    await context.setOffline(true);
    await expectFlutterText(page, /You are offline.*Showing saved data/i);
    await context.setOffline(false);
    await expectFlutterText(page, /Connection restored.*Syncing/i);
    await context.close();
  });

  test('CHO record workspace exposes search, filters, export, and role-specific planning support', async ({browser}, testInfo) => {
    const identity = {...identities().cho, expectedRoute: '**/cho/dashboard'};
    const {context, page} = await signOutToIsolatedContext(browser, testInfo.project, identity);
    await openFlutterRoute(page, '/cho/patients');
    await expectFlutterText(page, /Patient/i);
    await expectFlutterText(page, /Export CSV/i);
    await openFlutterRoute(page, '/cho/dashboard');
    await expectFlutterText(page, /City Health Planning Support/i);
    await context.close();
  });
});
