require('dotenv').config();

if (process.env.GRACECONNECT_ENABLE_LEGACY_BACKEND !== 'true') {
  console.error(
    'The legacy Grace Connect Express/Mongo backend is archived and disabled. ' +
      'The active app backend is Supabase. Set GRACECONNECT_ENABLE_LEGACY_BACKEND=true only for local archaeology.'
  );
  process.exit(1);
}

const express = require('express');
const mongoose = require('mongoose');
const app = express();

console.log('Starting server...'); // Added for debugging

app.use(express.json());

// MongoDB Connection with database name added
const uri = process.env.MONGODB_URI;
mongoose.connect(uri, {
  serverSelectionTimeoutMS: 30000, // 30 seconds timeout for connection
  socketTimeoutMS: 30000 // 30 seconds for socket
})
  .then(() => console.log('Connected to MongoDB'))
  .catch(err => console.error('Connection error:', err));

// Define Schemas
const memberSchema = new mongoose.Schema({
  name: String,
  email: String,
  phone: String,
  joinDate: Date,
  status: String
});
const eventSchema = new mongoose.Schema({
  title: String,
  date: String,
  time: String,
  rsvp: Boolean
});
const prayerSchema = new mongoose.Schema({
  type: String,
  request: String,
  status: String
});

const Member = mongoose.model('Member', memberSchema);
const Event = mongoose.model('Event', eventSchema);
const Prayer = mongoose.model('Prayer', prayerSchema);

// API Endpoints with error handling
app.get('/members', async (req, res) => {
  try {
    const members = await Member.find().timeout(30000);
    res.json(members);
  } catch (err) {
    console.error('Query error:', err);
    res.status(500).json({ error: 'Query timed out or failed. Please try again.' });
  }
});

app.post('/members', async (req, res) => {
  try {
    const member = new Member(req.body);
    await member.save();
    res.json(member);
  } catch (err) {
    res.status(500).json({ error: 'Save failed' });
  }
});

app.get('/events', async (req, res) => {
  try {
    const events = await Event.find().timeout(30000);
    res.json(events);
  } catch (err) {
    console.error('Query error:', err);
    res.status(500).json({ error: 'Query timed out or failed. Please try again.' });
  }
});

app.post('/events', async (req, res) => {
  try {
    const event = new Event(req.body);
    await event.save();
    res.json(event);
  } catch (err) {
    res.status(500).json({ error: 'Save failed' });
  }
});

app.get('/prayers', async (req, res) => {
  try {
    const prayers = await Prayer.find().timeout(30000);
    res.json(prayers);
  } catch (err) {
    console.error('Query error:', err);
    res.status(500).json({ error: 'Query timed out or failed. Please try again.' });
  }
});

app.post('/prayers', async (req, res) => {
  try {
    const prayer = new Prayer(req.body);
    await prayer.save();
    res.json(prayer);
  } catch (err) {
    res.status(500).json({ error: 'Save failed' });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
