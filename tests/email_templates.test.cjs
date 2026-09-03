const assert = require('node:assert/strict');

const {
  buildAccountOnboardingEmail,
  buildPasswordResetActionUrl,
  buildPortalLoginUrl,
  buildReferralAssignmentEmail,
} = require('../functions/email_templates');

const accountEmail = buildAccountOnboardingEmail({
  fullName: 'Dr. Ada <Test>',
  email: 'ada@example.test',
  role: 'DOCTOR',
  activationUrl: 'https://www.ai-dsuhis.com/activate?token=controlled-test',
  activationExpiresInMinutes: 5,
});
assert.equal(accountEmail.subject, 'Your AI-DSUHIS Account Is Ready');
assert.match(accountEmail.html, /AI-DSUHIS/);
assert.match(accountEmail.html, /Set up your account/);
assert.match(accountEmail.html, /ada@example.test/);
assert.match(accountEmail.html, /Dr\. Ada &lt;Test&gt;/);
assert.match(accountEmail.html, /expires in 5 minutes/i);
assert.match(accountEmail.html, /Open Doctor Login Portal/);
assert.match(accountEmail.html, /https:\/\/www\.ai-dsuhis\.com\/doctor\/login/);
assert.match(accountEmail.text, /https:\/\/www\.ai-dsuhis\.com\/doctor\/login/);
assert.doesNotMatch(accountEmail.html, /temporary password/i);

assert.equal(buildPortalLoginUrl('DOCTOR'), 'https://www.ai-dsuhis.com/doctor/login');
assert.equal(buildPortalLoginUrl('CHO'), 'https://www.ai-dsuhis.com/cho/login');

const customResetUrl = buildPasswordResetActionUrl(
  'https://capstone-c98f9.firebaseapp.com/__/auth/action?mode=resetPassword&oobCode=one-time-code&apiKey=test-api-key&lang=en',
);
assert.match(customResetUrl, /^https:\/\/www\.ai-dsuhis\.com\/auth\/reset-password\?/);
assert.match(customResetUrl, /mode=resetPassword/);
assert.match(customResetUrl, /oobCode=one-time-code/);
assert.match(customResetUrl, /apiKey=test-api-key/);

const referralEmail = buildReferralAssignmentEmail({
  doctorName: 'Ada Test',
  referralId: 'REF-2026-0001',
  referral: {
    patientName: 'Controlled Patient',
    referralDate: 'September 3, 2026 2:00 PM',
    barangay: 'Test Barangay',
    createdByName: 'Test BHW',
    referralReason: 'Follow-up assessment',
    priority: 'routine',
    status: 'assigned',
  },
});
assert.equal(referralEmail.subject, 'New Patient Referral Assigned – AI-DSUHIS');
assert.match(referralEmail.html, /New referral assigned/);
assert.match(referralEmail.html, /REF-2026-0001/);
assert.match(referralEmail.html, /Controlled Patient/);
assert.match(referralEmail.html, /View referral/);
assert.match(referralEmail.html, /doctor\/dashboard\?referralId=REF-2026-0001/);
assert.match(referralEmail.html, /Open Doctor Login Portal/);
assert.match(referralEmail.html, /https:\/\/www\.ai-dsuhis\.com\/doctor\/login/);
assert.match(referralEmail.text, /https:\/\/www\.ai-dsuhis\.com\/doctor\/login/);
assert.doesNotMatch(referralEmail.html, /medical history|AI prediction|clinical notes/i);
assert.match(referralEmail.text, /AI-DSUHIS/);

console.log('Email template tests passed.');
