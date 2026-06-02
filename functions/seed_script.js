const admin = require('firebase-admin');
const serviceAccount = require('./service_account.json'); // We might not have this, we can try default credential if running in cloud, but locally we need auth. 
// Actually, 'firebase-admin' can often imply default creds if we use `firebase run` or similar, but here we are in a terminal.
// Strategy shift: We can use the existing `flutter run` environment or similar? No.
// Better: We can simpler use the 'Developer Console' approach the user ALREADY has code for?
// The user said "nothing is being populated". They are stuck effectively. 
// If they can't login, they can't seed.
// I will write this script to use 'applicationDefault' credentials. The user might need to run `gcloud auth application-default login` but let's try.

// Wait, I don't have the user's service account key. 
// Using the client app to seed is easier if I can force it.
// But I can't force clicks.

// customized approach:
// Modification of `main.dart` or `ChurchService` to seed on app start if empty?
// That's a good robust fix. "If churches collection is empty, seed it".

admin.initializeApp();
const db = admin.firestore();

const initialChurches = [
    "Yallahs NTCOG",
    "Wirefence NTCOG",
    "West Prospect NTCOG",
    "Temple Hall NTCOG",
    "Stettin NTCOG",
    "Steer Town NTCOG",
    "St. Ann’s Bay NTCOG",
    "Spanish Town NTCOG",
    "Spalding NTCOG",
    "Siloah NTCOG",
    "Savanna-La-Mar NTCOG",
    "Santa Cruz NTCOG",
    "Sanguinetti NTCOG",
    "Sandy Bay NTCOG",
    "Salem NTCOG",
    "Rocky Settlement NTCOG",
    "Rock River NTCOG",
    "Riverside NTCOG",
    "Porus NTCOG",
    "Portmore NTCOG",
    "Port Antonio NTCOG",
    "Parks Road NTCOG",
    "Palmer’s Cross NTCOG",
    "Oracabessa NTCOG",
    "Old Harbour NTCOG",
    "Ocho Rios NTCOG",
    "Newport NTCOG",
    "New Market NTCOG",
    "Negril NTCOG",
    "Mountain View NTCOG"
];

async function seed() {
    console.log('Seeding churches...');
    const batch = db.batch();

    for (const name of initialChurches) {
        const docRef = db.collection('churches').doc();
        batch.set(docRef, {
            id: docRef.id,
            name: name,
            // Create a case-insensitive search field
            name_lowercase: name.toLowerCase(),
            placeId: 'manual_' + docRef.id,
            address: 'Jamaica',
            denomination: 'New Testament Church of God',
            status: 'verified',
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            membersCount: 0
        });
    }

    await batch.commit();
    console.log('Done!');
}

seed();
