/**
 * BrainVault — Keep-Alive Utility
 *
 * Prevents two free-tier services from sleeping:
 *
 * 1. Render (backend host):
 *    Spins down after 15 min of inactivity. We self-ping every 14 min.
 *
 * 2. Supabase (database):
 *    Pauses free projects after 1 week of inactivity. We touch the DB
 *    with a lightweight SELECT on every ping cycle.
 */

const cron = require('node-cron');
const { ping: pingDB } = require('../services/database');

/**
 * Start the keep-alive cron schedule.
 * Runs every 14 minutes to stay under Render's 15-minute timeout.
 *
 * @param {number} port - The Express server port (for self-ping URL)
 */
function startKeepAlive(port) {
  // Skip keep-alive in development — no need to self-ping locally
  if (process.env.NODE_ENV === 'development') {
    console.log('[KEEPALIVE] Skipped (development mode)');
    return;
  }

  // Cron: every 14 minutes ("At minute 0, 14, 28, 42, 56")
  cron.schedule('*/14 * * * *', async () => {
    const timestamp = new Date().toISOString();

    try {
      // 1. Self-ping the HTTP health endpoint
      // RENDER_EXTERNAL_URL is auto-set by Render's environment
      const baseUrl =
        process.env.RENDER_EXTERNAL_URL || `http://localhost:${port}`;

      const httpRes = await fetch(`${baseUrl}/api/health`);
      const serverOk = httpRes.ok;

      // 2. Ping Supabase to register DB activity
      const dbOk = await pingDB();

      console.log(
        `[KEEPALIVE] ${timestamp} | Server: ${serverOk ? 'OK' : 'FAIL'} | DB: ${dbOk ? 'OK' : 'FAIL'}`
      );
    } catch (err) {
      console.error(`[KEEPALIVE] ${timestamp} | Error: ${err.message}`);
    }
  });

  console.log('[KEEPALIVE] Cron scheduled — pinging every 14 minutes');
}

module.exports = { startKeepAlive };
