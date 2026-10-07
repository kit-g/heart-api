-- Heart's scheduled database jobs: work that only touches data runs here, in
-- Postgres, not on AWS. pg_cron lives in the `postgres` database (Supabase
-- pins it there); each job runs in the app's database, :'db'.
--
-- scripts/schedule_jobs.sh applies this on every deploy. Re-running it
-- updates each job by name, so this file is the whole truth: a job removed
-- here must also be unscheduled (cron.unschedule) in the same change.

-- 04:17 UTC daily: OAuth rows no flow can use any more
SELECT cron.schedule_in_database('oauth-cleanup', '17 4 * * *', 'SELECT _clean_up_oauth()', :'db');

-- 04:47 UTC daily: pg_cron's own run log, which otherwise grows forever
SELECT cron.schedule(
    'cron-history-cleanup',
    '47 4 * * *',
    $$DELETE FROM cron.job_run_details WHERE end_time < now() - interval '14 days'$$
);
