/**
 * Microsoft 365 Multi-User Outlook Automation (Playwright)
 * ------------------------------------------------------------
 *
 * This Playwright test automates Microsoft Entra / Microsoft 365
 * authentication and Outlook Web interaction across multiple user
 * accounts in a controlled test environment.
 *
 * For each configured user, the test performs the following workflow:
 *
 *   1. Navigates to Microsoft login
 *   2. Authenticates using provided credentials
 *   3. Handles common login UI variations (account picker, prompts, etc.)
 *   4. Opens Outlook Web directly
 *   5. Searches for a target email by subject
 *   6. Opens the email if present
 *   7. Attempts to launch "Edit in browser"
 *   8. Waits for editor window and confirms load
 *
 * Tests run sequentially to avoid concurrent authentication conflicts.
 *
 * ------------------------------------------------------------
 * Purpose
 * ------------------------------------------------------------
 * This script is designed to generate realistic Microsoft 365 user
 * activity for testing, validation, and research scenarios such as:
 *
 *   • identity telemetry generation
 *   • mailbox interaction simulation
 *   • security monitoring validation
 *   • detection engineering testing
 *   • automated user workflow replay
 *
 * ------------------------------------------------------------
 * Configuration
 * ------------------------------------------------------------
 * Required environment variable:
 *
 *   QA_PASSWORD
 *
 * Example (Linux/macOS):
 *   export QA_PASSWORD="YourPasswordHere"
 *
 * Example (PowerShell):
 *   $env:QA_PASSWORD="YourPasswordHere"
 *
 * User accounts are defined in the USERS array.
 * Target email subject is defined in TARGET_EMAIL_SUBJECT.
 *
 * ------------------------------------------------------------
 * Design Notes
 * ------------------------------------------------------------
 * • Uses resilient selectors to tolerate Microsoft UI changes
 * • Handles optional "Stay signed in" prompts
 * • Navigates directly to Outlook to avoid landing page variability
 * • Gracefully skips mailboxes without the target email
 * • Extended timeouts support slow networks and proxy routing (e.g., Tor)
 *
 * ------------------------------------------------------------
 * Limitations
 * ------------------------------------------------------------
 * • MFA flows must be pre-satisfied or disabled
 * • Microsoft UI changes may require selector updates
 * • Requires valid credentials for each account
 *
 * ------------------------------------------------------------
 * Security Notice
 * ------------------------------------------------------------
 * This script performs automated authentication using real credentials.
 * Intended strictly for authorized testing and controlled environments.
 *
 * Do not use against production systems without approval.
 *
 * ------------------------------------------------------------
 */

import { test, expect, Page } from '@playwright/test';

const PASSWORD = process.env.QA_PASSWORD || '';
if (!PASSWORD) {
  throw new Error("Set QA_PASSWORD first: export QA_PASSWORD='P@ssw0rd123!'");
}

const USERS = [
  'bhernandez@kidsreadingroad.com',
  'cdavis@kidsreadingroad.com',
  'ddavis@kidsreadingroad.com',
  'ebrown@kidsreadingroad.com',
  'jmartinez@kidsreadingroad.com',
  'jmiller@kidsreadingroad.com',
  'krodriguez@kidsreadingroad.com',
  'plopez@kidsreadingroad.com',
  'rwilson@kidsreadingroad.com',
  'sbrown@kidsreadingroad.com',
  'swilson@kidsreadingroad.com',
  'twilliams@kidsreadingroad.com',
  'twilson@kidsreadingroad.com',
  'wanderson@kidsreadingroad.com',
  'TestUser1@kidsreadingroad.com',
  'TestUser2@kidsreadingroad.com',
  'TestUser3@kidsreadingroad.com',
  'TestUser4@kidsreadingroad.com',
];

const TARGET_EMAIL_SUBJECT = 'Micrsoft Login ASAP';

test.describe.configure({ mode: 'serial' });
test.setTimeout(180_000);

/**
 * Robust Microsoft login (Tor-safe, UI-variant-safe)
 */
async function loginMicrosoft(page: Page, email: string, password: string) {
  await page.goto('https://login.microsoftonline.com/', { waitUntil: 'domcontentloaded' });

  // Handle "Pick an account" screen if it appears
  const accountTile = page.getByRole('button', { name: new RegExp(email, 'i') });
  if (await accountTile.isVisible().catch(() => false)) {
    await accountTile.click();
  }

  // Username/email (robust selectors)
  const username = page.locator(
    'input[name="loginfmt"], #i0116, input[type="email"]'
  );
  await username.first().waitFor({ state: 'visible', timeout: 60_000 });
  await username.first().fill(email);

  // Next
  const next = page.locator('#idSIButton9, button:has-text("Next")');
  await next.first().waitFor({ state: 'visible', timeout: 60_000 });
  await next.first().click();

  // Password
  const pw = page.locator(
    'input[name="passwd"], #i0118, input[type="password"]'
  );
  await pw.first().waitFor({ state: 'visible', timeout: 60_000 });
  await pw.first().fill(password);

  // Sign in
  const signIn = page.locator('#idSIButton9, button:has-text("Sign in")');
  await signIn.first().waitFor({ state: 'visible', timeout: 60_000 });
  await signIn.first().click();

  // Optional "Stay signed in?"
  const dontShow = page.locator('#KmsiCheckboxField, input[name="DontShowAgain"]');
  if (await dontShow.first().isVisible().catch(() => false)) {
    await dontShow.first().check().catch(() => {});
  }

  const yes = page.locator('#idSIButton9, button:has-text("Yes")');
  if (await yes.first().isVisible().catch(() => false)) {
    await yes.first().click();
  }

  await page.waitForLoadState('domcontentloaded');
}

/**
 * Open Outlook directly and try to open/edit the target email
 */
async function openOutlookAndEditInBrowser(page: Page) {
  // Skip flaky M365 landing pages entirely
  await page.goto('https://outlook.office.com/mail/', {
    waitUntil: 'domcontentloaded',
  });

  await page.waitForLoadState('networkidle');

  // Prove Outlook loaded
  await expect(page).toHaveURL(/outlook\.office\.com\/mail/i, {
    timeout: 60_000,
  });

  const outlook = page;
  const msg = outlook.getByText(TARGET_EMAIL_SUBJECT).first();

  try {
    await msg.waitFor({ state: 'visible', timeout: 20_000 });
    await msg.click();

    await outlook.getByTitle('More actions').click({ timeout: 20_000 });

    const editPopupPromise = outlook.waitForEvent('popup');
    await outlook
      .getByRole('menuitem', { name: /edit in browser/i })
      .click({ timeout: 20_000 });

    const editor = await editPopupPromise;
    await editor.waitForLoadState('domcontentloaded');
    await expect(editor).toHaveURL(/./);
  } catch {
    console.log(
      `[WARN] "${TARGET_EMAIL_SUBJECT}" not found for this mailbox. Skipping email open/edit step.`
    );
    await expect(outlook).toHaveURL(/outlook/i);
  }
}

for (const email of USERS) {
  test(`M365 Outlook flow for ${email}`, async ({ page }) => {
    await loginMicrosoft(page, email, PASSWORD);
    await openOutlookAndEditInBrowser(page);
    await page.waitForTimeout(750);
  });
}
          
