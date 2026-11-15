/**
 * Example Cloud Function (Node.js) to generate yearly summaries for users.
 * Deploy with Firebase Functions and schedule via Cloud Scheduler / pubsub.
 * This is a template — adapt collection names, field mapping, and auth as needed.
 */

const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
admin.initializeApp();

// Scheduled to run once per year (example cron: every Jan 1st at 00:00)
exports.scheduledYearlySummaries = functions.pubsub.schedule('0 0 1 1 *')
  .timeZone('UTC')
  .onRun(async (context) => {
    const db = getFirestore(admin.getApp());
    // Fetch all patient records or iterate users collection
    const patientsSnap = await db.collection('patient_records').get();
    const nowYear = new Date().getUTCFullYear() - 1; // generate for previous year

    for (const doc of patientsSnap.docs) {
      const data = doc.data();
      // Example: gather metrics for that patient
      const patientId = doc.id;
      const metricsSnap = await db.collection('patient_records')
        .doc(patientId)
        .collection('metrics')
        .where('timestamp', '>=', new Date(Date.UTC(nowYear,0,1)))
        .where('timestamp', '<', new Date(Date.UTC(nowYear+1,0,1)))
        .get();

      const records = metricsSnap.docs.map(d => d.data());
      // TODO: call summarizer (could be a separate HTTP function that accepts records)
      const summaryText = `Auto-generated yearly summary for ${nowYear}: ${records.length} records.`;

      await db.collection('summaries').add({
        patientId,
        year: nowYear,
        type: 'yearly',
        text: summaryText,
        generatedAt: FieldValue.serverTimestamp(),
      });
    }

    return null;
  });
