const functions = require('firebase-functions');
const nodemailer = require('nodemailer');

// This address is the system identity. SMTP credentials must remain in the
// Functions runtime configuration; the sender identity is intentionally not
// accepted from client payloads.
const SYSTEM_MAILER_EMAIL = 'aidsuhis@gmail.com';
const SYSTEM_MAILER_FROM = `AI-DSUHIS <${SYSTEM_MAILER_EMAIL}>`;

let transporter = null;
let transporterReason = null;

function runtimeSmtpConfig() {
  let configured = {};
  try {
    configured = (functions.config && functions.config().smtp) || {};
  } catch (error) {
    configured = {};
  }

  return {
    host: process.env.SMTP_HOST || configured.host,
    port: Number(process.env.SMTP_PORT || configured.port || 587),
    secure: String(
        process.env.SMTP_SECURE ?? configured.secure ?? 'false',
    ).toLowerCase() === 'true',
    user: process.env.SMTP_USER || configured.user,
    pass: process.env.SMTP_PASSWORD || process.env.SMTP_PASS || configured.password || configured.pass,
  };
}

function getSystemMailer() {
  if (transporter || transporterReason) {
    return {transporter, reason: transporterReason};
  }

  const config = runtimeSmtpConfig();
  if (!config.host || !config.user || !config.pass) {
    transporterReason = 'smtp_not_configured';
    return {transporter: null, reason: transporterReason};
  }

  if (String(config.user).trim().toLowerCase() !== SYSTEM_MAILER_EMAIL) {
    transporterReason = 'system_mailer_mismatch';
    console.error('SMTP_USER must be the configured AI-DSUHIS system mailer address.');
    return {transporter: null, reason: transporterReason};
  }

  try {
    transporter = nodemailer.createTransport({
      host: config.host,
      port: config.port,
      secure: config.secure,
      auth: {user: SYSTEM_MAILER_EMAIL, pass: config.pass},
    });
    return {transporter, reason: null};
  } catch (error) {
    transporterReason = 'smtp_initialization_failed';
    console.error('Could not initialize the AI-DSUHIS system mailer.', error);
    return {transporter: null, reason: transporterReason};
  }
}

async function sendSystemEmail({to, subject, text, html}) {
  const recipient = String(to || '').trim().toLowerCase();
  if (!recipient) return {sent: false, reason: 'missing_recipient'};

  const mailer = getSystemMailer();
  if (!mailer.transporter) {
    return {sent: false, reason: mailer.reason || 'smtp_unavailable'};
  }

  try {
    const result = await mailer.transporter.sendMail({
      from: SYSTEM_MAILER_FROM,
      to: recipient,
      subject: String(subject || 'AI-DSUHIS notification'),
      text: String(text || ''),
      html: html ? String(html) : undefined,
    });
    return {sent: true, reason: 'sent', messageId: result.messageId || null};
  } catch (error) {
    console.error('AI-DSUHIS system email failed.', {
      code: error?.code || 'unknown',
      message: error?.message || String(error),
    });
    return {sent: false, reason: 'send_failed'};
  }
}

module.exports = {
  SYSTEM_MAILER_EMAIL,
  SYSTEM_MAILER_FROM,
  sendSystemEmail,
};
