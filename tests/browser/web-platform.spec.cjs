const {test, expect} = require('@playwright/test');

const identities = () => JSON.parse(process.env.BROWSER_TEST_IDENTITIES || '{}');

const bhwRoutes = [
  ['/bhw/dashboard', /Barangay Health Operations/i, 'Dashboard'],
  ['/bhw/patients', /Patient Records/i, 'Patient Records'],
  ['/bhw/checkups', /Check-up Management/i, 'Check-ups'],
  ['/bhw/prenatal', /Prenatal Care/i, 'Prenatal'],
  ['/bhw/immunization', /Immunization Management/i, 'Immunization'],
  ['/bhw/communicable', /Communicable Disease Management/i, 'Communicable'],
  ['/bhw/non-communicable', /Non-Communicable Disease Management/i, 'Non-Communicable'],
  ['/bhw/morbidity', /Morbidity Records/i, 'Morbidity'],
  ['/bhw/mortality', /Mortality Monitoring/i, 'Mortality'],
  ['/bhw/referrals', /Referral Records/i, 'Referrals'],
  ['/bhw/summary', /Health Summary|Summary/i, 'Summary Generation'],
  ['/bhw/analytics', /Analytics/i, 'Analytics'],
  ['/bhw/profile', /User Details|Profile/i, 'Profile and Settings'],
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

async function openAuthenticatedRoute(page, route, expectedRoute = route) {
  // The web app uses Flutter's path URL strategy. Navigating by hash here
  // leaves the browser on the previous route and makes an otherwise healthy
  // authenticated page look like a timeout.
  await page.goto(route, {waitUntil: 'domcontentloaded'});
  const expectedPath = new URL(expectedRoute, 'http://127.0.0.1').pathname;
  await page.waitForFunction(
    (destination) => window.location.pathname === destination,
    expectedPath,
    {timeout: 30_000},
  );
  await page.locator('flutter-view').waitFor({state: 'attached'});
  await enableFlutterSemantics(page);
}

async function navigateBhwMenu(page, label) {
  const isMobile = (page.viewportSize()?.width ?? 0) < 760;
  const mobileMenuButton = page.getByRole('button', {name: /Open navigation menu/i});
  if (isMobile) {
    await expect(mobileMenuButton).toBeVisible({timeout: 30_000});
    await mobileMenuButton.click();
    await enableFlutterSemantics(page);
  }
  const escapedLabel = label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  await page
    .getByRole('button', {name: new RegExp(`^${escapedLabel}`, 'i')})
    .first()
    .click();
}

async function openBhwMobileNavigation(page) {
  const isMobile = (page.viewportSize()?.width ?? 0) < 760;
  if (!isMobile) return;
  const mobileMenuButton = page.getByRole('button', {name: /Open navigation menu/i});
  await expect(mobileMenuButton).toBeVisible({timeout: 30_000});
  await mobileMenuButton.click();
  await enableFlutterSemantics(page);
}

async function expectFlutterText(page, text) {
  const semantics = page.locator('flt-semantics-host');
  const visibleText = semantics.getByText(text).first();
  const accessibleLabel = semantics.getByLabel(text).first();
  await expect(visibleText.or(accessibleLabel).first()).toBeVisible({
    timeout: 30_000,
  });
}

async function enterFlutterText(field, value) {
  await field.click();
  // Flutter swaps the semantics input for its editable overlay on the first
  // keystroke. Prime that swap before entering the value so the first real
  // character is not discarded.
  await field.pressSequentially('x', {delay: 15});
  await field.press('ControlOrMeta+A');
  await field.press('Backspace');
  await field.pressSequentially(value, {delay: 15});
  await expect(field).toHaveValue(value);
}

async function login(page, identity, loginRoute = '/login', heading = /Welcome back/i) {
  await openFlutterRoute(page, loginRoute);
  await expectFlutterText(page, heading);

  const emailField = page.getByRole('textbox', {name: /you@example.com|email/i}).first();
  await enterFlutterText(emailField, identity.email);

  const passwordField = page.getByRole('textbox', {
    name: /enter your password|password/i,
  }).first();
  await enterFlutterText(passwordField, identity.password);
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
      ['/doctor/login', /Doctor Portal Login/i],
      ['/signup', /Create|Register/i],
      ['/cho/signup', /AI-DSUHIS/i],
      ['/forgot-password', /Forgot|Reset/i],
      ['/auth/reset-password', /Secure link unavailable/i],
      ['/not-found', /Page not found|not found/i],
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
    for (const route of [
      '/bhw/patients?view=records',
      '/cho/reports',
      '/doctor/referrals',
      '/doctor/dashboard',
      '/doctor/archive',
      '/doctor/profile',
      '/checkups?view=records',
      '/prenatal',
      '/morbidity',
      '/mortality',
      '/CommunicablePage',
      '/NonCommunicablePage',
      '/ReferralsPage',
      '/bhw-profile',
      '/cho/bhwManagement',
      '/cho/dataQuality',
      '/cho/auditLogs',
    ]) {
      await openFlutterRoute(page, route);
      await expect(page).toHaveURL(/\/login$/);
      await expectFlutterText(page, /Welcome back/i);
    }
  });
});

test.describe('authentication retry recovery', () => {
  for (const [route, heading, identityKey, expectedRoute] of [
    ['/login', /Welcome back/i, 'doctor', '**/doctor/dashboard'],
    ['/bhw/login', /BHW Portal Login/i, 'bhw', '**/bhw/dashboard'],
    ['/cho/login', /CHO Portal Login/i, 'cho', '**/cho/dashboard'],
    ['/doctor/login', /Doctor Portal Login/i, 'doctor', '**/doctor/dashboard'],
  ]) {
    test(`${route} remains usable after invalid credentials`, async ({page}) => {
      const identity = identities()[identityKey];
      await openFlutterRoute(page, route);
      await expectFlutterText(page, heading);

      const emailField = page
        .getByRole('textbox', {name: /you@example.com|email/i})
        .first();
      const passwordField = page
        .getByRole('textbox', {name: /enter your password|password/i})
        .first();
      const signInButton = page.getByRole('button', {name: /^Sign in$/i});

      await enterFlutterText(emailField, identity.email);
      await enterFlutterText(passwordField, 'Wrong-QA-Password-123!');
      await signInButton.click();

      await expectFlutterText(page, /Invalid email or password/i);
      await expect(signInButton).toBeEnabled({timeout: 30_000});
      await expect(emailField).toBeEditable();
      await expect(passwordField).toBeEditable();

      // The second attempt uses the same page, fields, and focused browser
      // session. A refresh must not be needed to recover the form.
      await enterFlutterText(emailField, identity.email);
      await enterFlutterText(passwordField, identity.password);
      await signInButton.click();
      await expectFlutterText(page, /Login successful/i);
      await page
        .getByRole('button', {name: /Open (Dashboard|CHO Dashboard|Doctor Dashboard)/i})
        .click();
      await page.waitForURL(expectedRoute, {timeout: 30_000});
    });
  }
});

test.describe('role routes and permissions', () => {
  test('BHW canonical routes stay BHW-scoped', async ({browser}, testInfo) => {
    const identity = {...identities().bhw, expectedRoute: '**/bhw/dashboard'};
    const {context, page} = await signOutToIsolatedContext(browser, testInfo.project, identity);
    for (const [, heading, menuLabel] of bhwRoutes) {
      await navigateBhwMenu(page, menuLabel);
      await expectFlutterText(page, heading);
      await expect(page.getByText(/Workspace unavailable/i)).toHaveCount(0);
    }
    await openAuthenticatedRoute(page, '/cho/dashboard');
    await expectFlutterText(page, /Workspace unavailable/i);
    await context.close();
  });

  test('CHO routes work but governance routes remain admin-only', async ({browser}, testInfo) => {
    const identity = {...identities().cho, expectedRoute: '**/cho/dashboard'};
    const {context, page} = await signOutToIsolatedContext(browser, testInfo.project, identity);
    for (const [route, heading] of choRoutes) {
      await openAuthenticatedRoute(page, route);
      await expectFlutterText(page, heading);
      await expect(page.getByText(/Workspace unavailable/i)).toHaveCount(0);
    }
    await openAuthenticatedRoute(page, '/cho/super-admin');
    await expectFlutterText(page, /Workspace unavailable/i);
    await context.close();
  });

  test('doctor is limited to the Doctor Portal workflow', async ({browser}, testInfo) => {
    const identity = {...identities().doctor, expectedRoute: '**/doctor/dashboard'};
    const doctorContext = await browser.newContext({viewport: testInfo.project.use.viewport});
    const doctorPage = await doctorContext.newPage();
    await login(doctorPage, identity, '/doctor/login', /Doctor Portal Login/i);
    await expectFlutterText(doctorPage, /Doctor Dashboard|Assigned referrals/i);
    await expectFlutterText(
      doctorPage,
      /Good (Morning|Noon|Afternoon|Evening), Dr\. Browser QA Doctor/i,
    );
    await expectFlutterText(doctorPage, /\d{1,2}:\d{2} (AM|PM) PHT/i);
    await openAuthenticatedRoute(doctorPage, '/doctor/archive');
    await expectFlutterText(doctorPage, /Referral Archive/i);
    await openAuthenticatedRoute(doctorPage, '/doctor/profile');
    await expectFlutterText(doctorPage, /Doctor Profile/i);
    await openAuthenticatedRoute(doctorPage, '/bhw/dashboard');
    await expectFlutterText(doctorPage, /Workspace unavailable/i);
    await openAuthenticatedRoute(doctorPage, '/cho/dashboard');
    await expectFlutterText(doctorPage, /Workspace unavailable/i);
    await doctorContext.close();
  });

  test('doctor sidebar keeps active navigation and supports collapse on every viewport', async ({browser}, testInfo) => {
    const identity = {...identities().doctor, expectedRoute: '**/doctor/dashboard'};
    const doctorContext = await browser.newContext({viewport: testInfo.project.use.viewport});
    const doctorPage = await doctorContext.newPage();
    await login(doctorPage, identity, '/doctor/login', /Doctor Portal Login/i);

    if ((doctorPage.viewportSize()?.width ?? 0) < 760) {
      await doctorPage.getByRole('button', {name: /Open navigation menu/i}).click();
      await enableFlutterSemantics(doctorPage);
    }

    const expandSidebar = doctorPage.getByRole('button', {name: /Expand sidebar/i});
    const collapseSidebar = doctorPage.getByRole('button', {name: /Collapse sidebar/i});
    const isMobile = (doctorPage.viewportSize()?.width ?? 0) < 760;

    if (isMobile) {
      await expectFlutterText(doctorPage, /Doctor Portal/i);
      await expectFlutterText(doctorPage, /Archive/i);
      await expect(collapseSidebar).toBeVisible();
      await collapseSidebar.click();
      await expect(expandSidebar).toBeVisible();
      await expandSidebar.click();
      await expect(collapseSidebar).toBeVisible();
    }

    // Desktop-sized shells below the compact breakpoint start as a 72px rail
    // to preserve usable content width. Mobile drawers intentionally open in
    // the expanded-label mode.
    const viewport = doctorPage.viewportSize();
    const startsCompact =
      (viewport?.width ?? 0) >= 760 &&
      ((viewport?.width ?? 0) < 960 || (viewport?.height ?? 0) < 840);
    if (startsCompact) {
      await expect(expandSidebar).toBeVisible();
      await expandSidebar.click();
    } else {
      await expect(collapseSidebar).toBeVisible();
    }
    await expect(collapseSidebar).toBeVisible();
    await collapseSidebar.click();
    await expect(expandSidebar).toBeVisible();
    await expect(
      doctorPage.getByRole('button', {name: /Dashboard navigation item/i}),
    ).toBeVisible();

    await expandSidebar.click();
    await expect(collapseSidebar).toBeVisible();

    await doctorPage
      .getByRole('button', {name: /Archive navigation item/i})
      .click();
    await doctorPage.waitForURL('**/doctor/archive', {timeout: 30_000});
    if (isMobile) {
      await doctorPage.getByRole('button', {name: /Open navigation menu/i}).click();
      await enableFlutterSemantics(doctorPage);
    }
    await expect(
      doctorPage.getByRole('button', {name: /Archive navigation item/i}),
    ).toBeVisible();
    await doctorContext.close();
  });

  test('doctor archive exposes a searchable city-wide barangay picker', async ({browser}, testInfo) => {
    const identity = {...identities().doctor, expectedRoute: '**/doctor/dashboard'};
    const doctorContext = await browser.newContext({viewport: testInfo.project.use.viewport});
    const doctorPage = await doctorContext.newPage();
    await login(doctorPage, identity, '/doctor/login', /Doctor Portal Login/i);
    await openAuthenticatedRoute(doctorPage, '/doctor/archive');

    await doctorPage
      .getByRole('button', {name: /^Barangay All barangays$/i})
      .click();
    await expectFlutterText(doctorPage, /Select Barangay/i);
    const barangaySearch = doctorPage.getByRole('textbox', {name: /Search all barangays/i});
    await enterFlutterText(barangaySearch, 'Saint Peter');
    await expectFlutterText(doctorPage, /Saint Peter/i);
    await doctorPage
      .getByRole('button', {name: /^Saint Peter Basakan District$/i})
      .click();
    await expect(
      doctorPage.getByRole('button', {name: /^Barangay Saint Peter$/i}),
    ).toBeVisible();
    await doctorContext.close();
  });

  test('super-admin can use CHO and governance routes but not BHW pages', async ({browser}, testInfo) => {
    const identity = {...identities().superAdmin, expectedRoute: '**/cho/super-admin'};
    const {context, page} = await signOutToIsolatedContext(browser, testInfo.project, identity);
    await expectFlutterText(page, /User Governance|Super Admin/i);
    for (const route of [
      '/cho/dashboard',
      '/cho/role-manager',
      '/cho/manage-access',
      '/cho/super-admin',
      '/cho/bhw-management',
    ]) {
      await openAuthenticatedRoute(page, route);
      await expect(page.getByText(/Workspace unavailable/i)).toHaveCount(0);
    }
    await openAuthenticatedRoute(page, '/bhw/patients');
    await expectFlutterText(page, /Workspace unavailable/i);
    await context.close();
  });
});

test.describe('critical controls and connection feedback', () => {
  test('BHW patient search, view switch, add action, and offline banner remain usable', async ({browser}, testInfo) => {
    const identity = {...identities().bhw, expectedRoute: '**/bhw/dashboard'};
    const {context, page} = await signOutToIsolatedContext(browser, testInfo.project, identity);
    await openBhwMobileNavigation(page);
    const notificationButton = page.getByRole('button', {name: /Notifications navigation item/i});
    await expect(notificationButton).toBeVisible();
    await expect(
      page.getByRole('button', {name: /Download the AI-DSUHIS BHW Android application APK/i}),
    ).toBeVisible();
    await notificationButton.click();
    const closeNotifications = page.getByRole('button', {name: /Close notifications/i});
    await expect(closeNotifications).toBeVisible();
    await closeNotifications.click();
    await openAuthenticatedRoute(page, '/bhw/patients');
    await expectFlutterText(page, /Patient Records/i);
    await page.getByRole('button', {name: /^Records$/i}).click();
    await expectFlutterText(page, /Search by name/i);
    await expect(page.getByRole('button', {name: /Add Patient/i})).toBeVisible();

    await context.setOffline(true);
    await expect.poll(() => page.evaluate(() => navigator.onLine)).toBe(false);
    await page.evaluate(() => window.dispatchEvent(new Event('offline')));
    await expect(page.getByRole('status').filter({hasText: /You are offline.*Showing saved data/i})).toBeVisible();
    await context.setOffline(false);
    await page.evaluate(() => window.dispatchEvent(new Event('online')));
    await expect(page.getByRole('status').filter({hasText: /Connection restored.*Syncing/i})).toBeVisible();
    await context.close();
  });

  test('CHO record workspace exposes search, filters, export, and role-specific planning support', async ({browser}, testInfo) => {
    const identity = {...identities().cho, expectedRoute: '**/cho/dashboard'};
    const {context, page} = await signOutToIsolatedContext(browser, testInfo.project, identity);
    await openAuthenticatedRoute(page, '/cho/patients');
    await expectFlutterText(page, /Patient/i);
    await expectFlutterText(page, /Export CSV/i);
    await openAuthenticatedRoute(page, '/cho/reports');
    await expectFlutterText(page, /CHO planning decision support/i);
    await context.close();
  });
});
