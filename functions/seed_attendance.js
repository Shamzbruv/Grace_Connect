const admin = require('firebase-admin');

// Initialize Firebase Admin
// Try standard initialization which looks for GOOGLE_APPLICATION_CREDENTIALS or default auth
try {
    admin.initializeApp();
} catch (e) {
    console.error('Error initializing Firebase Admin:', e);
    console.log('\nTo run this script locally, you need authentication.');
    console.log('Try running: gcloud auth application-default login');
    console.log('OR set GOOGLE_APPLICATION_CREDENTIALS to your key file path.');
    process.exit(1);
}

const db = admin.firestore();

async function seedAttendanceData() {
    console.log('Starting Attendance Data Seeding...');

    // 1. Get a Church to attach data to
    const churchesSnap = await db.collection('churches').limit(1).get();
    if (churchesSnap.empty) {
        console.error('No churches found! Please run the church seed script first.');
        return;
    }

    const churchDoc = churchesSnap.docs[0];
    const churchId = churchDoc.id;
    const churchName = churchDoc.data().name;
    console.log(`Targeting Church: ${churchName} (${churchId})`);

    // 2. Create Church Location (using Kingston, Jamaica coordinates stub)
    // Real coordinates should be updated by the user in the app, but this enables the feature.
    const locationData = {
        churchId: churchId,
        latitude: 18.0179, // Example: Kingston
        longitude: -76.8099,
        radiusMeters: 200.0,
        placeId: `loc_${churchId}`,
        timezone: 'America/Jamaica',
        address: 'Kingston, Jamaica' // Optional metadata
    };

    await db.collection('church_locations').doc(locationData.placeId).set(locationData);
    console.log(' - Created Church Location');

    // Update the Church doc to link to this location if not already
    // The app logic looks up 'users' -> 'placeId', but good to have reference.
    // NOTE: The APP logic uses `users` -> `placeId`. We need to ensure the TEST USER has this placeId.
    // We can't easily adhere to "current user" here without Auth ID.
    // Output instructions to linking.

    // 3. Create Service Schedules (Every day 6 AM - 10 PM to ensure "Now" is covered for testing)
    const days = [1, 2, 3, 4, 5, 6, 7]; // Mon-Sun
    const batch = db.batch();

    for (const day of days) {
        const serviceId = `svc_${churchId}_${day}`;
        const scheduleData = {
            serviceId: serviceId,
            churchId: churchId,
            name: 'Daily Test Service',
            dayOfWeek: day,
            startTime: '06:00',
            endTime: '22:00'
        };
        const ref = db.collection('service_schedules').doc(serviceId);
        batch.set(ref, scheduleData);
    }

    await batch.commit();
    console.log(' - Created Service Schedules (Mon-Sun, 6am-10pm)');

    console.log('\nSUCCESS! Database seeded.');
    console.log('IMPORTANT: For the app to work, ensure your User Profile is linked to this Church Location.');
    console.log(`1. Go to Firestore -> users -> [your_uid]`);
    console.log(`2. Set field 'placeId' to: '${locationData.placeId}'`);
}

seedAttendanceData().catch(console.error);
