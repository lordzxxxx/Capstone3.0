// Shared email-safe presentation for AI-DSUHIS notifications.
// Keep dynamic values escaped and keep the complete patient record inside the
// authenticated portal rather than in an email body.

function escapeHtml(value) {
  return String(value ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
}

function textValue(value, fallback = 'Not provided') {
  const text = String(value ?? '').trim();
  return text || fallback;
}

function dateValue(value) {
  if (value && typeof value.toDate === 'function') {
    return value.toDate().toLocaleString('en-PH', {hour12: true});
  }
  if (value instanceof Date) {
    return value.toLocaleString('en-PH', {hour12: true});
  }
  if (typeof value === 'number') {
    return new Date(value).toLocaleString('en-PH', {hour12: true});
  }
  return textValue(value);
}

function row(label, value) {
  return `<tr>
    <td style="padding:9px 12px;border-bottom:1px solid #d9e5f2;color:#4b6075;font-size:13px;width:38%;vertical-align:top;">${escapeHtml(label)}</td>
    <td style="padding:9px 12px;border-bottom:1px solid #d9e5f2;color:#0b1f3a;font-size:13px;font-weight:600;vertical-align:top;">${escapeHtml(value)}</td>
  </tr>`;
}

function buildLayout({title, preheader = '', greeting, intro, rows = [], ctaLabel, ctaUrl, closing = 'This is an automated system notification.'}) {
  const safeUrl = escapeHtml(ctaUrl);
  const tableRows = rows.map((entry) => row(entry.label, entry.value)).join('');
  const textRows = rows.map((entry) => `${entry.label}: ${entry.value}`).join('\n');
  const text = [
    greeting,
    '',
    intro,
    ...(textRows ? ['', textRows] : []),
    '',
    `${ctaLabel}: ${ctaUrl}`,
    '',
    'For privacy and security, complete patient and clinical information is available only after secure sign-in.',
    '',
    'AI-DSUHIS',
    'City Health Office',
    closing,
  ].join('\n');
  const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escapeHtml(title)}</title></head>
<body style="margin:0;padding:0;background:#f5f7fa;color:#0b1f3a;font-family:Arial,Helvetica,sans-serif;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;">${escapeHtml(preheader)}</div>
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background:#f5f7fa;padding:24px 12px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:640px;background:#ffffff;border:1px solid #d9e5f2;border-radius:14px;overflow:hidden;">
        <tr><td style="background:#071a33;padding:22px 28px;color:#ffffff;">
          <div style="font-size:20px;font-weight:700;letter-spacing:.2px;">AI-DSUHIS</div>
          <div style="font-size:12px;color:#d4e3f2;margin-top:4px;">City Health Office Portal</div>
        </td></tr>
        <tr><td style="padding:30px 28px 26px;">
          <h1 style="margin:0 0 18px;color:#0b1f3a;font-size:24px;line-height:1.25;">${escapeHtml(title)}</h1>
          <p style="margin:0 0 12px;color:#0b1f3a;font-size:15px;line-height:1.55;">${escapeHtml(greeting)}</p>
          <p style="margin:0 0 20px;color:#4b6075;font-size:14px;line-height:1.6;">${escapeHtml(intro)}</p>
          ${tableRows ? `<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="border:1px solid #d9e5f2;border-radius:10px;overflow:hidden;margin:0 0 24px;">${tableRows}</table>` : ''}
          <div style="text-align:center;margin:24px 0 26px;">
            <a href="${safeUrl}" style="display:inline-block;background:#2f80ed;color:#ffffff;text-decoration:none;font-size:14px;font-weight:700;padding:13px 22px;border-radius:9px;">${escapeHtml(ctaLabel)}</a>
          </div>
          <p style="margin:0;color:#4b6075;font-size:13px;line-height:1.6;">For privacy and security, complete patient and clinical information is available only after secure sign-in.</p>
        </td></tr>
        <tr><td style="background:#edf3fa;border-top:1px solid #d9e5f2;padding:18px 28px;color:#4b6075;font-size:12px;line-height:1.55;">
          <strong style="color:#0b1f3a;">AI-DSUHIS</strong><br>City Health Office<br>${escapeHtml(closing)}
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`;
  return {text, html};
}

function buildAccountOnboardingEmail({fullName, email, role, activationUrl}) {
  const name = textValue(fullName, 'Doctor');
  return {
    subject: 'Your AI-DSUHIS Account Is Ready',
    ...buildLayout({
      title: 'Your account is ready',
      preheader: 'Set up your secure AI-DSUHIS account.',
      greeting: `Hello ${name},`,
      intro: 'A City Health Office Administrator created your AI-DSUHIS account. Use the secure link below to set your password and access the portal.',
      rows: [
        {label: 'Registered email', value: textValue(email)},
        {label: 'Account role', value: textValue(role)},
      ],
      ctaLabel: 'Set up your account',
      ctaUrl: activationUrl,
      closing: 'Do not share your account credentials or activation link.',
    }),
  };
}

/**
 * Send Firebase action codes to the portal's branded action handler instead
 * of the generic Firebase Hosting widget. Keep only the action parameters
 * needed by the client-side Firebase SDK and fall back to the original link
 * if the generated link is incomplete.
 */
function buildPasswordResetActionUrl(resetLink) {
  try {
    const source = new URL(String(resetLink));
    const mode = source.searchParams.get('mode');
    const oobCode = source.searchParams.get('oobCode');
    const apiKey = source.searchParams.get('apiKey');
    if (!mode || !oobCode || !apiKey) return resetLink;

    const portalUrl = String(process.env.APP_URL || 'https://www.ai-dsuhis.com').replace(/\/$/, '');
    const actionUrl = new URL('/auth/reset-password', `${portalUrl}/`);
    actionUrl.searchParams.set('mode', mode);
    actionUrl.searchParams.set('oobCode', oobCode);
    actionUrl.searchParams.set('apiKey', apiKey);
    const lang = source.searchParams.get('lang');
    if (lang) actionUrl.searchParams.set('lang', lang);
    return actionUrl.toString();
  } catch (_) {
    return resetLink;
  }
}

function buildReferralAssignmentEmail({doctorName, referralId, referral, transferred = false, previousDoctorName = ''}) {
  const doctor = textValue(doctorName, 'Doctor');
  const patient = textValue(referral?.patientName || referral?.patientInformation?.fullName, 'Patient');
  const referralDate = dateValue(referral?.referralDateTime || referral?.referralDate || referral?.createdAt);
  const portalUrl = String(process.env.APP_URL || 'https://www.ai-dsuhis.com').replace(/\/$/, '');
  const link = `${portalUrl}/doctor/dashboard?referralId=${encodeURIComponent(referralId)}`;
  const subject = transferred ? 'Referral Reassigned to You – AI-DSUHIS' : 'New Patient Referral Assigned – AI-DSUHIS';
  const intro = transferred
    ? `A referral has been transferred to you in AI-DSUHIS by the City Health Office. ${previousDoctorName ? `It was previously assigned to ${previousDoctorName}.` : ''}`.trim()
    : 'A new patient referral has been automatically assigned to you in AI-DSUHIS.';
  return {
    subject,
    ...buildLayout({
      title: transferred ? 'Referral reassigned to you' : 'New referral assigned',
      preheader: transferred ? 'A referral is now in your secure Doctor Portal.' : 'A new referral is waiting in your secure Doctor Portal.',
      greeting: `Hello Dr. ${doctor},`,
      intro,
      rows: [
        {label: 'Patient', value: patient},
        {label: 'Referral reference', value: referralId},
        {label: 'Referral date and time', value: referralDate},
        {label: 'Barangay', value: textValue(referral?.barangay || referral?.barangayName)},
        {label: 'Referral source', value: textValue(referral?.createdByName || referral?.bhwName || referral?.createdByEmail, 'Referring BHW')},
        {label: 'Referral reason', value: textValue(referral?.referralReason || referral?.reason || referral?.chiefComplaint)},
        {label: 'Priority', value: textValue(referral?.priority || referral?.referralPriority, 'Routine')},
        {label: 'Assigned doctor', value: doctor},
        {label: 'Status', value: textValue(referral?.status, 'assigned')},
      ],
      ctaLabel: 'View referral',
      ctaUrl: link,
      closing: 'This is an automated system notification. Complete medical information remains inside the secured AI-DSUHIS system.',
    }),
  };
}

module.exports = {
  buildAccountOnboardingEmail,
  buildPasswordResetActionUrl,
  buildReferralAssignmentEmail,
};
