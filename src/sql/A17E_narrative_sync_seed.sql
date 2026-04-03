-- feature_flags (A1 V8.0)
INSERT INTO feature_flags (flag_name, enabled, description)
VALUES ('ENABLE_NARRATIVE_SYNC', false, 'Narrative Sync™: B2B-exclusive convergence timeline')
ON CONFLICT (flag_name) DO NOTHING;

-- tier_features (A13B): B2B only
INSERT INTO tier_features (tier, flag_name, enabled, config) VALUES
  ('free',      'ENABLE_NARRATIVE_SYNC', false, '{}'),
  ('pro',       'ENABLE_NARRATIVE_SYNC', false, '{}'),
  ('pro_plus',  'ENABLE_NARRATIVE_SYNC', false, '{}'),
  ('b2b',       'ENABLE_NARRATIVE_SYNC', true,  '{}')
ON CONFLICT (tier, flag_name) DO NOTHING;
