ALTER TABLE SitesHumans.Sites
ALTER COLUMN fieldproperties
SET DEFAULT JSON_OBJECT(
  'StartDate', '2023-06-1',
  'FC', 38,
  'WP', 18,
  'WA', 0.5,
  'IE', 0.65,
  'Crop', 'Potato',
  'area', 0,
  'type', 'channel',
  'humanID', 10001
);

