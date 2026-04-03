-- ========================================================================
-- PM-TW.1: posted_tweets table for dedup + audit trail
-- ========================================================================

INSERT INTO feature_flags (flag_name, enabled, description)
VALUES (
  'ENABLE_AUTO_TWEETER',
  false,
  'Gates the X auto-tweeter workflow. When disabled, n8n workflow exits early. Independent of all other feature flags.'
)
ON CONFLICT (flag_name) DO NOTHING;

CREATE TABLE IF NOT EXISTS posted_tweets (
  tweet_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  x_tweet_id        TEXT,
  content_type      TEXT NOT NULL CHECK (content_type IN (
                      'score_spike', 'variance_flag', 'vote_contradiction',
                      'mutation_hook', 'spending_hook', 'crossover_moment'
                    )),
  figure_id         UUID,
  bill_id           TEXT,
  tweet_text        TEXT NOT NULL,
  template_id       TEXT NOT NULL,
  shareability      NUMERIC(5,4),
  posted_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  status            TEXT NOT NULL DEFAULT 'posted' CHECK (status IN (
                      'posted', 'failed', 'skipped'
                    )),
  error_message     TEXT,

  CONSTRAINT posted_tweets_content_type_valid
    CHECK (content_type IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_posted_tweets_figure_recent
  ON posted_tweets(figure_id, posted_at DESC)
  WHERE figure_id IS NOT NULL AND status = 'posted';

CREATE INDEX IF NOT EXISTS idx_posted_tweets_type_recent
  ON posted_tweets(content_type, posted_at DESC)
  WHERE status = 'posted';

CREATE INDEX IF NOT EXISTS idx_posted_tweets_chronological
  ON posted_tweets(posted_at DESC);

-- Calendar-day count index
CREATE INDEX IF NOT EXISTS idx_posted_tweets_daily
  ON posted_tweets(posted_at)
  WHERE status = 'posted';

ALTER TABLE posted_tweets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS posted_tweets_service_only ON posted_tweets;
CREATE POLICY posted_tweets_service_only ON posted_tweets
  FOR ALL USING (false);

REVOKE ALL ON TABLE posted_tweets FROM anon, authenticated;
GRANT ALL ON TABLE posted_tweets TO service_role;

DROP TRIGGER IF EXISTS prevent_posted_tweet_mutation ON posted_tweets;
CREATE TRIGGER prevent_posted_tweet_mutation
  BEFORE UPDATE OR DELETE ON posted_tweets
  FOR EACH ROW
  EXECUTE FUNCTION prevent_immutable_mutation();
-- Returns count of tweets posted today (calendar day, UTC).
-- Used by n8n daily limit check.

CREATE OR REPLACE FUNCTION count_todays_tweets()
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT COUNT(*)::INTEGER
  FROM posted_tweets
  WHERE status = 'posted'
    AND posted_at::date = CURRENT_DATE;
$$;

REVOKE ALL ON FUNCTION count_todays_tweets() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION count_todays_tweets() TO service_role;
