CREATE TABLE settings.general (
   setting_key TEXT PRIMARY KEY,
   setting_value BLOB NOT NULL,
   frecency_date REAL
) STRICT;

CREATE TABLE settings.shortcuts (
    target TEXT PRIMARY KEY,
    alias TEXT,
    hotkey TEXT
) STRICT;

CREATE TABLE settings.extension_settings (
    extension_id TEXT NOT NULL,
    setting_key TEXT NOT NULL,
    setting_value BLOB NOT NULL,
    frecency_date REAL,
    PRIMARY KEY (extension_id, setting_key)

CREATE TABLE settings_v2.internal_extensions_new (
    id TEXT NOT NULL PRIMARY KEY,
    enabled INTEGER NOT NULL DEFAULT 1,
    deprecated_meta TEXT,
    enabled_fallback_command_ids TEXT,
    synced_meta TEXT,
    local_meta TEXT,
    macos_synced_meta TEXT,
    windows_synced_meta TEXT,
    updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE settings_v2.node_extensions_new (
    id TEXT NOT NULL PRIMARY KEY,
    enabled INTEGER NOT NULL DEFAULT 1,
    deprecated_meta TEXT,
    oauthTokens TEXT,
    localStorage TEXT,
    storedValues TEXT,
    enabled_fallback_command_ids TEXT,
    synced_meta TEXT,
    local_meta TEXT,
    macos_synced_meta TEXT,
    windows_synced_meta TEXT,
    updated_at TEXT NOT NULL DEFAULT(RAYDATE()),
    uninstalled INTEGER NOT NULL DEFAULT 0,
    device_generations TEXT NOT NULL DEFAULT '{}'
) STRICT, WITHOUT ROWID;

CREATE TABLE settings_v2.commands_new (
    id TEXT NOT NULL PRIMARY KEY,
    extension_id TEXT NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    alias TEXT,
    deprecated_hotkey TEXT,
    deprecated_meta TEXT,
    custom_subtitle TEXT,
    assumed_view_kind TEXT,
    favorite_order REAL DEFAULT NULL,
    fallback_order REAL DEFAULT NULL,
    status_item TEXT,
    synced_meta TEXT,
    local_meta TEXT,
    macos_synced_meta TEXT,
    windows_synced_meta TEXT,
    updated_at TEXT NOT NULL DEFAULT(RAYDATE()),
    macos_hotkey TEXT,
    windows_hotkey TEXT,
    device_generations TEXT NOT NULL DEFAULT '{}'
) STRICT, WITHOUT ROWID;

CREATE INDEX settings_v2.idx_commands_extension_id ON commands(extension_id);

CREATE TABLE settings_v2.general_settings_new (
    id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
    open_at_login INTEGER NOT NULL DEFAULT 1,
    show_in_menu_bar INTEGER NOT NULL DEFAULT 1,
    follow_system_appearance INTEGER NOT NULL DEFAULT 1,
    theme_id TEXT NOT NULL DEFAULT 'bundled-raycast-dark',
    window_mode TEXT NOT NULL DEFAULT 'expanded',
    global_hotkey TEXT,
    favicon_provider TEXT,
    pop_to_root_timeout INTEGER NOT NULL DEFAULT 90,
    escape_key_behavior TEXT NOT NULL DEFAULT 'pop-back-or-close',
    page_navigation_keys TEXT NOT NULL DEFAULT 'square-brackets',
    use_system_proxy_settings INTEGER NOT NULL DEFAULT 0,
    additional_certificate_authorities TEXT NOT NULL DEFAULT '[]',
    window_presentation_mode TEXT NOT NULL DEFAULT 'mouse-screen',
    enforced_input_source_id TEXT,
    navigation_bindings TEXT NOT NULL DEFAULT 'emacs',
    window_capture_hotkey TEXT DEFAULT NULL,
    window_capture_copy_to_clipboard INTEGER NOT NULL DEFAULT 1,
    window_capture_show_in_finder INTEGER NOT NULL DEFAULT 0,
    window_capture_cleanshotx_overlay INTEGER NOT NULL DEFAULT 0,
    window_capture_custom_wallpaper TEXT DEFAULT NULL,
    root_search_sensitivity TEXT NOT NULL DEFAULT 'medium',
    updated_at TEXT NOT NULL DEFAULT(RAYDATE()),
    FOREIGN KEY (theme_id) REFERENCES themes(id),
    FOREIGN KEY (window_mode) REFERENCES window_modes(id)

CREATE TABLE settings_v2.general_settings_new (
  id TEXT NOT NULL PRIMARY KEY DEFAULT '0000000000GENERA1SETT1NGS0',
  open_at_login INTEGER NOT NULL DEFAULT 1,
  show_in_menu_bar INTEGER NOT NULL DEFAULT 1,
  appearance TEXT NOT NULL DEFAULT 'system',
  theme_dark_id TEXT,
  theme_light_id TEXT,
  window_mode TEXT NOT NULL DEFAULT 'expanded',
  global_hotkey TEXT,
  favicon_provider TEXT,
  pop_to_root_timeout INTEGER NOT NULL DEFAULT 90,
  escape_key_behavior TEXT NOT NULL DEFAULT 'pop-back-or-close',
  page_navigation_keys TEXT NOT NULL DEFAULT 'square-brackets',
  use_system_proxy_settings INTEGER NOT NULL DEFAULT 0,
  additional_certificate_authorities TEXT NOT NULL DEFAULT '[]',
  window_presentation_mode TEXT NOT NULL DEFAULT 'mouse-screen',
  enforced_input_source_id TEXT,
  navigation_bindings TEXT NOT NULL DEFAULT 'emacs',
  root_search_sensitivity TEXT NOT NULL DEFAULT 'medium',
  tidy_menu_bar INTEGER NOT NULL DEFAULT 0,
  builtin_hotkeys_preset TEXT NOT NULL DEFAULT 'improved',
  hyper_key_code TEXT DEFAULT NULL,
  hyper_key_include_shift INTEGER NOT NULL DEFAULT 1,
  hyper_key_caps_lock_action TEXT DEFAULT NULL,
  hyper_key_display_shortcut INTEGER NOT NULL DEFAULT 1,
  open_folders_in_tabs INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE settings_v2.cloud_sync_settings (
    id INTEGER NOT NULL DEFAULT 1 PRIMARY KEY CHECK (id = 1),
    enabled INTEGER NOT NULL DEFAULT 0,
    devices TEXT NOT NULL DEFAULT '[]',
    content TEXT NOT NULL DEFAULT '[]',
    connection TEXT NOT NULL DEFAULT '{}',
    enabled_at TEXT,
    updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE settings_v2.themes_new (
  id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
  name TEXT UNIQUE NOT NULL,
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE settings_v2.general_settings_new (
  id TEXT NOT NULL PRIMARY KEY DEFAULT '0000000000GENERA1SETT1NGS0',
  open_at_login INTEGER NOT NULL DEFAULT 1,
  show_in_menu_bar INTEGER NOT NULL DEFAULT 1,
  follow_system_appearance INTEGER NOT NULL DEFAULT 1,
  theme_id TEXT NOT NULL DEFAULT '0000000000THEMERAYDARK0000',
  window_mode TEXT NOT NULL DEFAULT 'expanded',
  global_hotkey TEXT,
  favicon_provider TEXT,
  pop_to_root_timeout INTEGER NOT NULL DEFAULT 90,
  escape_key_behavior TEXT NOT NULL DEFAULT 'pop-back-or-close',
  page_navigation_keys TEXT NOT NULL DEFAULT 'square-brackets',
  use_system_proxy_settings INTEGER NOT NULL DEFAULT 0,
  additional_certificate_authorities TEXT NOT NULL DEFAULT '[]',
  window_presentation_mode TEXT NOT NULL DEFAULT 'mouse-screen',
  enforced_input_source_id TEXT,
  navigation_bindings TEXT NOT NULL DEFAULT 'emacs',
  root_search_sensitivity TEXT NOT NULL DEFAULT 'medium',
  updated_at TEXT NOT NULL DEFAULT(RAYDATE()),
  FOREIGN KEY (theme_id) REFERENCES themes_new(id)

CREATE TABLE settings_v2.cloudsync_settings (
    id INTEGER NOT NULL DEFAULT 1 PRIMARY KEY CHECK (id = 1),
    enabled INTEGER NOT NULL DEFAULT 0,
    connection TEXT NOT NULL DEFAULT '{}',
    disabled_categories TEXT NOT NULL DEFAULT '[]',
    enabled_at TEXT,
    updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE settings_v2.themes (
    id TEXT PRIMARY KEY,
    name TEXT UNIQUE NOT NULL
) STRICT;

CREATE TABLE settings_v2.window_modes (
    id TEXT PRIMARY KEY,
    name TEXT UNIQUE NOT NULL
) STRICT;

CREATE TABLE settings_v2.general_settings (
    singleton_key INTEGER NOT NULL DEFAULT 1 PRIMARY KEY CHECK (singleton_key),
    open_at_login INTEGER NOT NULL DEFAULT 1,
    show_in_menu_bar INTEGER NOT NULL DEFAULT 1,
    follow_system_appearance INTEGER NOT NULL DEFAULT 1,
    theme_id TEXT NOT NULL DEFAULT 'bundled-raycast-dark',
    window_mode TEXT NOT NULL DEFAULT 'expanded',
    global_hotkey TEXT,
    FOREIGN KEY (theme_id) REFERENCES themes(id),
    FOREIGN KEY (window_mode) REFERENCES window_modes(id)

CREATE TABLE settings_v2.internal_extensions (
    id TEXT PRIMARY KEY,
    enabled INTEGER NOT NULL DEFAULT 1,
    meta TEXT
) STRICT;

create TABLE settings_v2.commands (
    id TEXT PRIMARY KEY,
    extension_id TEXT NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    favorited INTEGER NOT NULL DEFAULT 0,
    alias TEXT,
    hotkey TEXT,
    meta TEXT
) STRICT;ALTER TABLE settings_v2.general_settings ADD COLUMN page_navigation_keys TEXT NOT NULL DEFAULT 'square-brackets'; ALTER TABLE settings_v2.node_extensions ADD COLUMN device_generations TEXT NOT NULL DEFAULT '{}';
ALTER TABLE settings_v2.commands ADD COLUMN device_generations TEXT NOT NULL DEFAULT '{}';
ALTER TABLE settings_v2.commands RENAME COLUMN hotkey TO deprecated_hotkey;
ALTER TABLE settings_v2.commands ADD COLUMN macos_hotkey TEXT;
ALTER TABLE settings_v2.commands ADD COLUMN windows_hotkey TEXT;
CREATE TABLE settings_v2.node_extensions (
    id TEXT PRIMARY KEY,
    enabled INTEGER NOT NULL DEFAULT 1,
    meta TEXT,
    oauthTokens TEXT,
    localStorage TEXT,
    storedValues TEXT
) STRICT;
-- Rename meta -> deprecated_meta (kept for node-backend migration bootstrapper to read from)

CREATE TABLE settings_v2.themes_new (
  id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
  name TEXT NOT NULL UNIQUE,
  appearance TEXT NOT NULL,
  background TEXT NOT NULL,
  background_secondary TEXT NOT NULL,
  foreground TEXT NOT NULL,
  accent TEXT NOT NULL,
  selection TEXT NOT NULL,
  loader TEXT NOT NULL,
  red TEXT NOT NULL,
  orange TEXT NOT NULL,
  yellow TEXT NOT NULL,
  green TEXT NOT NULL,
  blue TEXT NOT NULL,
  purple TEXT NOT NULL,
  magenta TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE emoji.emoji (
  id INTEGER NOT NULL PRIMARY KEY,
  symbol TEXT NOT NULL,
	name TEXT NOT NULL,
  supportsSkinTones INTEGER NOT NULL DEFAULT FALSE,
  category TEXT NOT NULL,
  unicodeVersion REAL,
  frecencyDate REAL,
  pinned REAL
) STRICT;

-- Alias table
CREATE TABLE emoji.aliases (
  emoji_id INTEGER NOT NULL,
  alias TEXT NOT NULL,
  FOREIGN KEY (emoji_id) REFERENCES emoji(id)

CREATE TABLE emoji.keyword (
  emoji_id INTEGER NOT NULL,
  keyword TEXT NOT NULL,
  FOREIGN KEY(emoji_id) REFERENCES emoji(id)

CREATE TABLE emoji.custom_keyword (
  emoji_id INTEGER NOT NULL,
	keyword TEXT NOT NULL,
	FOREIGN KEY(emoji_id) REFERENCES emoji(id)

CREATE TABLE emoji.checksum (
  id INTEGER NOT NULL PRIMARY KEY,
  checksum BLOB NOT NULL
) STRICT;

-- Emoji FTS tables for search
CREATE VIRTUAL TABLE emoji.keyword_FTS USING FTS5(
  emoji_id,
  keyword,
  content='',
  content_rowid='id'
);

CREATE TRIGGER emoji.keyword_FTS_ai AFTER INSERT ON emoji.keyword BEGIN
  INSERT INTO keyword_FTS(rowid, keyword) VALUES (NEW.emoji_id, NEW.keyword);

CREATE TRIGGER emoji.keyword_FTS_ad AFTER DELETE ON emoji.keyword BEGIN
  INSERT INTO keyword_FTS(keyword_FTS, rowid, keyword) VALUES ('delete', OLD.emoji_id, OLD.keyword);

CREATE TRIGGER emoji.keyword_FTS_au AFTER UPDATE ON emoji.keyword BEGIN
  INSERT INTO keyword_FTS(keyword_FTS, rowid, keyword) VALUES ('delete', OLD.emoji_id, OLD.keyword);

CREATE TRIGGER emoji.keyword_FTS_ai_custom AFTER INSERT ON emoji.custom_keyword BEGIN
  INSERT INTO keyword_FTS(rowid, keyword) VALUES (NEW.emoji_id, NEW.keyword);

CREATE TRIGGER emoji.keyword_FTS_ad_custom AFTER DELETE ON emoji.custom_keyword BEGIN
  INSERT INTO keyword_FTS(keyword_FTS, rowid, keyword) VALUES ('delete', OLD.emoji_id, OLD.keyword);

CREATE TRIGGER emoji.keyword_FTS_au_custom AFTER UPDATE ON emoji.custom_keyword BEGIN
  INSERT INTO keyword_FTS(keyword_FTS, rowid, keyword) VALUES ('delete', OLD.emoji_id, OLD.keyword);

CREATE TRIGGER emoji.keyword_FTS_ai_alias AFTER INSERT ON emoji.aliases BEGIN
  INSERT INTO keyword_FTS(rowid, keyword) VALUES (NEW.emoji_id, NEW.alias);

CREATE TRIGGER emoji.keyword_FTS_ad_alias AFTER DELETE ON emoji.aliases BEGIN
  INSERT INTO keyword_FTS(keyword_FTS, rowid, keyword) VALUES ('delete', OLD.emoji_id, OLD.alias);

CREATE TRIGGER emoji.keyword_FTS_au_alias AFTER UPDATE ON emoji.aliases BEGIN
  INSERT INTO keyword_FTS(keyword_FTS, rowid, keyword) VALUES ('delete', OLD.emoji_id, OLD.alias);

CREATE TRIGGER emoji.keyword_FTS_ai_name AFTER INSERT ON emoji.emoji BEGIN
  INSERT INTO keyword_FTS(rowid, keyword) VALUES (NEW.id, NEW.name);

CREATE TRIGGER emoji.keyword_FTS_ad_name AFTER DELETE ON emoji.emoji BEGIN
  INSERT INTO keyword_FTS(keyword_FTS, rowid, keyword) VALUES ('delete', OLD.id, OLD.name);

CREATE TRIGGER emoji.keyword_FTS_au_name AFTER UPDATE ON emoji.emoji BEGIN
  INSERT INTO keyword_FTS(keyword_FTS, rowid, keyword) VALUES ('delete', OLD.id, OLD.name);

CREATE TABLE app_index.app (
  id INTEGER NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  path TEXT NOT NULL,
  localizedName TEXT,
  raycastId TEXT NOT NULL UNIQUE,
  applicationId TEXT NOT NULL,
  contentType INTEGER NOT NULL DEFAULT 0
) STRICT;

-- Index for faster lookups by applicationId
CREATE INDEX app_index.app_application_id_idx ON app(applicationId);

CREATE INDEX app_index.app_content_type_idx ON app(contentType);

CREATE TABLE currencies (
  code TEXT NOT NULL PRIMARY KEY,
  usd_rate REAL NOT NULL,
  currency_type TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
) strict, without rowid;

CREATE TRIGGER update_currencies_updated_at AFTER
UPDATE ON currencies FOR EACH ROW BEGIN
UPDATE currencies
SET
  updated_at = CURRENT_TIMESTAMP
WHERE
  code = OLD.code
  OR code = NEW.code;
END;

CREATE TABLE notes_new (
  id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
  title TEXT,
  text TEXT NOT NULL,
  raw_content TEXT,
  pinned REAL,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE()),
  deleted_at TEXT,
  last_accessed_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE org_transcription_styles (
  id TEXT NOT NULL PRIMARY KEY,
  organization_id TEXT NOT NULL,
  pack_id TEXT NOT NULL,
  style_id TEXT NOT NULL,
  value TEXT NOT NULL,
  remote_updated_at INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE mcp_servers (
  id TEXT NOT NULL PRIMARY KEY,
  type TEXT NOT NULL CHECK (type IN ('stdio', 'http')),
  icon TEXT NOT NULL,
  title TEXT NOT NULL,
  mention_name TEXT NOT NULL,
  description TEXT,
  built_in INTEGER NOT NULL DEFAULT 0 CHECK (built_in IN (0, 1)),
  error_message TEXT,
  last_connected TEXT,
  created_at TEXT NOT NULL,
  oauth_json TEXT CHECK (oauth_json IS NULL OR json_valid(oauth_json)),
  updated_at TEXT NOT NULL,
  command TEXT,
  arguments_json TEXT CHECK (arguments_json IS NULL OR json_valid(arguments_json)),
  environment_json TEXT CHECK (environment_json IS NULL OR json_valid(environment_json)),
  url TEXT,
  headers_json TEXT CHECK (headers_json IS NULL OR json_valid(headers_json)),
  oauth_config_json TEXT CHECK (oauth_config_json IS NULL OR json_valid(oauth_config_json)),
  tools_json TEXT NOT NULL CHECK (json_valid(tools_json)),
  CHECK (
    (type = 'stdio' AND command IS NOT NULL AND url IS NULL) OR
    (type = 'http' AND url IS NOT NULL AND command IS NULL)

CREATE INDEX mcp_servers_type_idx ON mcp_servers(type);

CREATE INDEX mcp_servers_mention_name_idx ON mcp_servers(mention_name);

CREATE TABLE calculator_history (
  id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
  expression TEXT NOT NULL UNIQUE,
  result TEXT NOT NULL,
  calculation_type TEXT NOT NULL DEFAULT 'unknown',
  copy_count INTEGER NOT NULL DEFAULT 1,
  pinned REAL,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE calculator_legacy_imports (
  migration_id TEXT NOT NULL,
  expression TEXT NOT NULL,
  PRIMARY KEY (migration_id, expression)

CREATE TABLE pending_tokens (
  token TEXT PRIMARY KEY,
  attempts INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
) STRICT;

CREATE TRIGGER update_pending_tokens_updated_at
AFTER UPDATE ON pending_tokens
FOR EACH ROW
BEGIN
  UPDATE pending_tokens
  SET updated_at = CURRENT_TIMESTAMP
  WHERE token = OLD.token;
END;

CREATE TABLE local_org_snippet_usage (
  snippet_id TEXT NOT NULL PRIMARY KEY,
  copy_count INTEGER NOT NULL DEFAULT 0,
  accessed_at TEXT NOT NULL DEFAULT(RAYDATE()),
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE local_org_snippet_tags (
  snippet_id TEXT NOT NULL PRIMARY KEY,
  tags TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE local_org_quicklink_tags (
  quicklink_id TEXT NOT NULL PRIMARY KEY,
  tags TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE screenshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    path TEXT NOT NULL UNIQUE,
    category TEXT NOT NULL CHECK (category IN ('ScreenCapture', 'ScreenRecording')),
    text TEXT,
    is_pinned INTEGER NOT NULL DEFAULT 0,
    pin_order INTEGER,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    text_extracted_at TEXT
) STRICT;

CREATE INDEX idx_screenshots_path ON screenshots(path);

CREATE INDEX idx_screenshots_pinned ON screenshots(is_pinned, pin_order);

CREATE INDEX idx_screenshots_modified ON screenshots(modified_at DESC);

CREATE TABLE IF NOT EXISTS quicklinks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    link TEXT NOT NULL,
    icon TEXT NOT NULL,
    application_id TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    open_count INTEGER DEFAULT 0
) STRICT;

CREATE TRIGGER quicklinks_updated_at AFTER UPDATE ON quicklinks
FOR EACH ROW
WHEN (OLD.name != NEW.name OR
      OLD.link != NEW.link OR
      OLD.icon != NEW.icon)

CREATE TABLE raycastConfiguration (
  extension_id TEXT PRIMARY KEY,
  configuration TEXT NOT NULL DEFAULT '{}',
  updated_at TEXT NOT NULL DEFAULT (RAYDATE())

CREATE TABLE user_defaults (
  key TEXT NOT NULL PRIMARY KEY,
  value TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_modified_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
) strict, without rowid;

CREATE TRIGGER update_user_defaults_last_modified_at AFTER
UPDATE ON user_defaults FOR EACH ROW BEGIN
UPDATE user_defaults
SET
  last_modified_at = CURRENT_TIMESTAMP
WHERE
  key = OLD.key
  OR key = NEW.key;

CREATE TRIGGER quicklinks_updated_at AFTER UPDATE ON quicklinks
FOR EACH ROW
WHEN (OLD.name != NEW.name OR
      OLD.link != NEW.link OR
      OLD.icon != NEW.icon OR
      OLD.raw_content != NEW.raw_content)

CREATE TABLE focus_categories (
  id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
  category_id TEXT NOT NULL UNIQUE,
  kind TEXT NOT NULL CHECK (kind IN ('builtin', 'custom')),
  builtin_id TEXT,
  title TEXT NOT NULL,
  icon TEXT NOT NULL,
  website_hosts_json TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(website_hosts_json)),
  application_ids_json TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(application_ids_json)),
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE()),
  accessed_at TEXT NOT NULL DEFAULT(RAYDATE()),
  CHECK (
    (kind = 'builtin' AND builtin_id IS NOT NULL) OR
    (kind = 'custom' AND builtin_id IS NULL)

CREATE UNIQUE INDEX focus_categories_builtin_id_idx ON focus_categories(builtin_id) WHERE builtin_id IS NOT NULL;
CREATE INDEX focus_categories_kind_accessed_title_idx ON focus_categories(kind, accessed_at DESC, title COLLATE NOCASE);

CREATE INDEX focus_categories_title_idx ON focus_categories(title COLLATE NOCASE);

CREATE TABLE quicklinks_new (
  id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
  name TEXT NOT NULL,
  link TEXT NOT NULL,
  raw_content TEXT NOT NULL DEFAULT '{"type":"doc","content":[{"type":"paragraph"}]}',
  icon TEXT NOT NULL,
  application_id TEXT,
  open_count INTEGER NOT NULL DEFAULT 0,
  open_with TEXT,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE router_quicklink_tag_new (
  quicklink_id TEXT NOT NULL,
  tag TEXT NOT NULL,
  PRIMARY KEY (quicklink_id, tag),
  FOREIGN KEY (quicklink_id) REFERENCES quicklinks_new(id) ON DELETE CASCADE
) STRICT, WITHOUT ROWID;

CREATE TABLE router_quicklink_tag (
    quicklink_id INTEGER NOT NULL,
    tag TEXT NOT NULL,
    FOREIGN KEY (quicklink_id) REFERENCES quicklinks(id),
    PRIMARY KEY (quicklink_id, tag)

CREATE TRIGGER update_quicklinks_updated_at_on_tag_insert AFTER
INSERT ON router_quicklink_tag FOR EACH ROW
BEGIN
  UPDATE quicklinks
  SET
    updated_at = CURRENT_TIMESTAMP
  WHERE
    id = NEW.quicklink_id;
END;

CREATE TRIGGER update_quicklinks_updated_at_on_tag_delete AFTER
DELETE ON router_quicklink_tag FOR EACH ROW
BEGIN
  UPDATE quicklinks
  SET
    updated_at = CURRENT_TIMESTAMP
  WHERE
    id = OLD.quicklink_id;
END;

CREATE TABLE translate_custom_commands (
  id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
  name TEXT NOT NULL,
  source_language TEXT NOT NULL DEFAULT 'auto',
  target_language TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE IF NOT EXISTS local_transcription_style_application_ids (
  style_id TEXT NOT NULL,
  application_id TEXT NOT NULL,
  position INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE()),
  PRIMARY KEY(style_id, application_id)

CREATE TABLE clipboard (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  text TEXT NOT NULL,
  file_path TEXT,
  image_hash TEXT,
  copy_count INTEGER NOT NULL DEFAULT 1,
  category TEXT DEFAULT 'text',
  rich_text_data BLOB,
  application_path TEXT,
  text_content TEXT,
  pinned DOUBLE,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_modified_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TRIGGER update_clipboard_last_modified_at AFTER
UPDATE ON clipboard FOR EACH ROW BEGIN
UPDATE clipboard
SET
  last_modified_at = CURRENT_TIMESTAMP
WHERE
  id = OLD.id;

CREATE TABLE notes_new (
  id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
  title TEXT,
  text TEXT NOT NULL,
  raw_content TEXT,
  pinned REAL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_modified_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TEXT,
  last_accessed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
) STRICT, WITHOUT ROWID;

CREATE TRIGGER update_notes_last_modified_at AFTER
UPDATE OF title, raw_content, text, pinned ON notes FOR EACH ROW BEGIN
UPDATE notes SET last_modified_at = CURRENT_TIMESTAMP WHERE id = OLD.id;
END;

CREATE TRIGGER update_snippets_last_modified_at AFTER
UPDATE ON snippets FOR EACH ROW 
WHEN (OLD.icon != NEW.icon OR 
      OLD.title != NEW.title OR 
      OLD.keyword != NEW.keyword OR 
      OLD.raw_content != NEW.raw_content OR 
      OLD.text != NEW.text OR
      OLD.pinned != NEW.pinned)

CREATE TABLE notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT,
    text TEXT NOT NULL,
    raw_content TEXT,
    pinned REAL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_modified_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
) STRICT;

CREATE TRIGGER update_notes_last_modified_at AFTER
UPDATE ON notes FOR EACH ROW BEGIN
UPDATE notes
SET
  last_modified_at = CURRENT_TIMESTAMP
WHERE
  id = OLD.id;
END;

CREATE TABLE snippets_new (
  id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
  icon TEXT NOT NULL,
  title TEXT NOT NULL,
  keyword TEXT,
  raw_content TEXT,
  text TEXT NOT NULL,
  copy_count INTEGER NOT NULL DEFAULT 0,
  pinned REAL,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE()),
  accessed_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE router_snippet_tag_new (
  snippet_id TEXT NOT NULL,
  tag TEXT NOT NULL,
  PRIMARY KEY (snippet_id, tag),
  FOREIGN KEY (snippet_id) REFERENCES snippets_new(id) ON DELETE CASCADE
) STRICT, WITHOUT ROWID;

CREATE TABLE apple_shortcuts (
  sort_order INTEGER NOT NULL PRIMARY KEY,
  shortcut_id TEXT,
  name TEXT NOT NULL,
  accepts_input INTEGER CHECK (accepts_input IN (0, 1)),
  folder_id TEXT,
  folder_name TEXT,
  image_path TEXT,
  updated_at TEXT NOT NULL DEFAULT (RAYDATE())

CREATE TABLE router_snippet_tag (
    snippet_id INTEGER NOT NULL,
    tag TEXT NOT NULL,
    FOREIGN KEY (snippet_id) REFERENCES snippets(id),
    PRIMARY KEY (snippet_id, tag)

CREATE TRIGGER update_snippets_last_modified_at_on_tag_insert AFTER
INSERT ON router_snippet_tag FOR EACH ROW
BEGIN
  UPDATE snippets
  SET
    last_modified_at = CURRENT_TIMESTAMP
  WHERE
    id = NEW.snippet_id;
END;

CREATE TRIGGER update_snippets_last_modified_at_on_tag_delete AFTER
DELETE ON router_snippet_tag FOR EACH ROW
BEGIN
  UPDATE snippets
  SET
    last_modified_at = CURRENT_TIMESTAMP
  WHERE
    id = OLD.snippet_id;
END;

CREATE TABLE windows_run_commands (
  id TEXT PRIMARY KEY DEFAULT (ULID()),
  alias TEXT NOT NULL,
  command TEXT NOT NULL,
  arguments TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  icon TEXT NOT NULL DEFAULT 'terminal',
  pinned REAL,
  times_executed INTEGER NOT NULL DEFAULT 0,
  last_executed_at TEXT,
  created_at TEXT NOT NULL DEFAULT (RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT (RAYDATE())

CREATE INDEX idx_windows_run_commands_alias ON windows_run_commands(alias);

CREATE INDEX idx_windows_run_commands_times_executed ON windows_run_commands(times_executed DESC);

CREATE INDEX idx_windows_run_commands_pinned_updated ON windows_run_commands(pinned, updated_at DESC);

CREATE TABLE windows_run_command_tag (
  command_id TEXT NOT NULL,
  tag TEXT NOT NULL,
  FOREIGN KEY (command_id) REFERENCES windows_run_commands(id) ON DELETE CASCADE,
  PRIMARY KEY (command_id, tag)

CREATE INDEX idx_windows_run_command_tag_tag ON windows_run_command_tag(tag);

CREATE TABLE org_ai_commands (
  id TEXT NOT NULL PRIMARY KEY,
  organization_id TEXT NOT NULL,
  pack_id TEXT NOT NULL,
  command_id TEXT NOT NULL,
  value TEXT NOT NULL,
  remote_updated_at INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE contacts (
  sort_order INTEGER NOT NULL PRIMARY KEY,
  contact_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  name TEXT,
  given_name TEXT,
  family_name TEXT,
  organization TEXT,
  phone_numbers TEXT,
  email_addresses TEXT,
  postal_addresses TEXT,
  image_data_available INTEGER NOT NULL DEFAULT 0 CHECK (image_data_available IN (0, 1)),
  updated_at TEXT NOT NULL DEFAULT (RAYDATE())

CREATE TABLE org_quicklinks (
  id TEXT NOT NULL PRIMARY KEY,
  organization_id TEXT NOT NULL,
  pack_id TEXT NOT NULL,
  name TEXT NOT NULL,
  link TEXT NOT NULL,
  icon TEXT NOT NULL,
  raw_content TEXT NOT NULL DEFAULT '{"type":"doc","content":[{"type":"paragraph"}]}',
  remote_updated_at INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE org_snippets (
  id TEXT NOT NULL PRIMARY KEY,
  organization_id TEXT NOT NULL,
  pack_id TEXT NOT NULL,
  icon TEXT NOT NULL,
  title TEXT NOT NULL,
  keyword TEXT,
  text TEXT NOT NULL,
  raw_content TEXT,
  remote_updated_at INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE org_pack_sync_state (
  kind TEXT NOT NULL PRIMARY KEY,
  last_synced_at INTEGER NOT NULL DEFAULT 0
) STRICT, WITHOUT ROWID;
-- Migration to:
-- 1. Remove application_id column from quicklinks table
-- 2. Replace open_with column with platform-specific columns (open_with_macos, open_with_windows, open_with_ios)

CREATE TABLE quicklinks_new (
  id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
  name TEXT NOT NULL,
  link TEXT NOT NULL,
  raw_content TEXT NOT NULL DEFAULT '{"type":"doc","content":[{"type":"paragraph"}]}',
  icon TEXT NOT NULL,
  open_count INTEGER NOT NULL DEFAULT 0,
  open_with_macos TEXT,
  open_with_windows TEXT,
  open_with_ios TEXT,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE router_quicklink_tag_new (
  quicklink_id TEXT NOT NULL,
  tag TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT(RAYDATE()),
  PRIMARY KEY (quicklink_id, tag),
  FOREIGN KEY (quicklink_id) REFERENCES quicklinks_new(id) ON DELETE CASCADE
) STRICT, WITHOUT ROWID;

CREATE TABLE snippets (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    icon TEXT NOT NULL,
    title TEXT NOT NULL,
    keyword TEXT,
    raw_content TEXT,
    text TEXT NOT NULL,
    copy_count INTEGER NOT NULL DEFAULT 0,
    pinned REAL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_modified_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    accessed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
) STRICT;

CREATE TRIGGER update_snippets_last_modified_at AFTER
UPDATE ON snippets FOR EACH ROW BEGIN
UPDATE snippets
SET
  last_modified_at = CURRENT_TIMESTAMP
WHERE
  id = OLD.id;

CREATE TABLE app_menu_bar_pins (
  app_id TEXT NOT NULL,
  menu_item_id TEXT NOT NULL,
  pinned REAL NOT NULL,
  PRIMARY KEY (app_id, menu_item_id)

CREATE INDEX app_menu_bar_pins_idx_app_pinned ON app_menu_bar_pins(app_id, pinned);

CREATE TABLE org_ai_agents (
  id TEXT NOT NULL PRIMARY KEY,
  organization_id TEXT NOT NULL,
  pack_id TEXT NOT NULL,
  agent_id TEXT NOT NULL,
  value TEXT NOT NULL,
  remote_updated_at INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE org_skills (
  id TEXT NOT NULL PRIMARY KEY,
  organization_id TEXT NOT NULL,
  organization_name TEXT NOT NULL,
  organization_handle TEXT NOT NULL,
  pack_id TEXT NOT NULL,
  skill_id TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  content TEXT NOT NULL,
  remote_updated_at INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE local_org_skill_settings (
  skill_id TEXT NOT NULL PRIMARY KEY,
  enabled INTEGER NOT NULL DEFAULT 0 CHECK(enabled IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE INDEX calculator_legacy_imports_expression ON calculator_legacy_imports (expression);

CREATE TRIGGER calculator_legacy_name_written AFTER UPDATE OF custom_name ON calculator_history
BEGIN
  UPDATE calculator_legacy_imports SET name_pending = 0 WHERE expression = OLD.expression;
END;

CREATE TRIGGER calculator_legacy_pin_written AFTER UPDATE OF pinned ON calculator_history
BEGIN
  UPDATE calculator_legacy_imports SET pin_pending = 0 WHERE expression = OLD.expression;
END;

CREATE TRIGGER calculator_legacy_entry_deleted AFTER DELETE ON calculator_history
BEGIN
  UPDATE calculator_legacy_imports SET name_pending = 0, pin_pending = 0 WHERE expression = OLD.expression;
END;

CREATE TABLE local_org_snippet_keywords (
  snippet_id TEXT NOT NULL PRIMARY KEY,
  keyword TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE notes_new (
  id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
  title TEXT,
  text TEXT NOT NULL,
  raw_content TEXT,
  pinned REAL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_modified_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
) STRICT, WITHOUT ROWID;

CREATE TABLE window_management_layout_groups (
  id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
  name TEXT NOT NULL,
  icon_name TEXT,
  created_at TEXT NOT NULL DEFAULT(RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE window_management_layouts (
  id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
  group_id TEXT NOT NULL REFERENCES window_management_layout_groups(id) ON DELETE CASCADE,
  position TEXT NOT NULL,
  size TEXT NOT NULL,
  offset TEXT NOT NULL,
  z_position INTEGER NOT NULL DEFAULT 0,
  source TEXT,
  display_index INTEGER,
  updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE INDEX window_management_layouts_group_id ON window_management_layouts(group_id);

CREATE TABLE router_snippet_tag_new (
  snippet_id TEXT NOT NULL,
  tag TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT(RAYDATE()),
  PRIMARY KEY (snippet_id, tag),
  FOREIGN KEY (snippet_id) REFERENCES snippets(id) ON DELETE CASCADE
) STRICT, WITHOUT ROWID;

CREATE TABLE searchMobile (
  search_id TEXT PRIMARY KEY,
  frequency INTEGER NOT NULL DEFAULT 1,
  last_used_at TEXT NOT NULL DEFAULT (RAYDATE()),
  created_at TEXT NOT NULL DEFAULT (RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT (RAYDATE()),
  type TEXT,
  favorite REAL,
  alias TEXT,
  keywords TEXT
) WITHOUT ROWID;

CREATE INDEX searchMobile_favorite_idx ON searchMobile(favorite) WHERE favorite IS NOT NULL;
CREATE INDEX searchMobile_type_idx ON searchMobile(type);

CREATE INDEX searchMobile_last_used_at_idx ON searchMobile(last_used_at);

CREATE TABLE keyboardSearchMobile (
  search_id TEXT PRIMARY KEY,
  frequency INTEGER NOT NULL DEFAULT 1,
  last_used_at TEXT NOT NULL DEFAULT (RAYDATE()),
  created_at TEXT NOT NULL DEFAULT (RAYDATE()),
  updated_at TEXT NOT NULL DEFAULT (RAYDATE()),
  type TEXT,
  favorite REAL,
  alias TEXT,
  keywords TEXT
) WITHOUT ROWID;

CREATE INDEX keyboardSearchMobile_favorite_idx ON keyboardSearchMobile(favorite) WHERE favorite IS NOT NULL;
CREATE INDEX keyboardSearchMobile_type_idx ON keyboardSearchMobile(type);

CREATE INDEX keyboardSearchMobile_last_used_at_idx ON keyboardSearchMobile(last_used_at);

CREATE TABLE frecency.root_search (
    item_id TEXT NOT NULL,
    frecency_date REAL,
    PRIMARY KEY (item_id)

CREATE VIRTUAL TABLE frecency.root_FTS USING FTS5(
  item_id,
  content='root_search'
);

CREATE TRIGGER frecency.root_FTS_ai AFTER INSERT ON frecency.root_search BEGIN
  INSERT INTO root_FTS(rowid, item_id) VALUES
   (NEW.rowid, NEW.item_id);

CREATE TRIGGER frecency.root_FTS_ad AFTER DELETE ON frecency.root_search BEGIN
  INSERT INTO root_FTS(root_FTS, rowid, item_id) VALUES ('delete', OLD.rowid, OLD.item_id);

CREATE TRIGGER frecency.root_FTS_au AFTER UPDATE ON frecency.root_search BEGIN
  INSERT INTO root_FTS(root_FTS, rowid, item_id) VALUES ('delete', OLD.rowid, OLD.item_id);

CREATE VIRTUAL TABLE frecency.root_FTS USING FTS5(
  item_id
);

CREATE TRIGGER frecency.root_FTS_ai AFTER INSERT ON frecency.root_search BEGIN
  INSERT INTO root_FTS(item_id) VALUES (NEW.item_id);

CREATE TRIGGER frecency.root_FTS_ad AFTER DELETE ON frecency.root_search BEGIN
  DELETE FROM root_FTS WHERE item_id = OLD.item_id;
END;

CREATE TRIGGER frecency.root_FTS_au AFTER UPDATE ON frecency.root_search WHEN OLD.item_id IS NOT NEW.item_id BEGIN
  DELETE FROM root_FTS WHERE item_id = OLD.item_id;
  INSERT INTO root_FTS(item_id) VALUES (NEW.item_id);

CREATE INDEX clipboard.index_entries_content_hash ON entries(content_hash);

CREATE TABLE clipboard.entries (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  workspace_id INTEGER NOT NULL DEFAULT 1,
  source_name TEXT NOT NULL,
  source_host INTEGER NOT NULL,
  source_url TEXT NOT NULL,
  copy_count INTEGER NOT NULL DEFAULT 1,
  pinned REAL,
  FOREIGN KEY(workspace_id) REFERENCES workspaces(id)

CREATE TABLE clipboard.items (
  id INTEGER NOT NULL,
  entry_id INTEGER NOT NULL,
  FOREIGN KEY (entry_id) REFERENCES entries(id),
  PRIMARY KEY (id, entry_id)

CREATE TABLE clipboard.representations (
  id INTEGER NOT NULL,
  item_id INTEGER NOT NULL,
  entry_id INTEGER NOT NULL,
  mime_type TEXT NOT NULL,
  content_type INTEGER NOT NULL,
  content TEXT NOT NULL,
  FOREIGN KEY (item_id, entry_id) REFERENCES items(id, entry_id),
  PRIMARY KEY (id, item_id)

CREATE TABLE clipboard.router_entry_category (
  entry_id INTEGER NOT NULL,
  category TEXT NOT NULL,
  FOREIGN KEY(entry_id) REFERENCES entries(id),
  PRIMARY KEY(entry_id, category)

CREATE TABLE clipboard.workspaces (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL
) STRICT;

-- Update an entry's "updated_at" field when it's updated
CREATE TRIGGER clipboard.update_entry_updated_at
AFTER UPDATE ON entries
WHEN old.updated_at <> current_timestamp
BEGIN
  UPDATE entries
    SET updated_at = CURRENT_TIMESTAMP
  WHERE id = OLD.id;
END;

CREATE VIRTUAL TABLE clipboard.representations_FTS USING FTS5(
  content,
  entry_title,
  content='representations',
  content_rowid='id'
);

CREATE TRIGGER clipboard.representations_FTS_ai AFTER INSERT ON clipboard.representations BEGIN
  INSERT INTO representations_FTS(rowid, content, entry_title)

CREATE TRIGGER clipboard.representations_FTS_ad AFTER DELETE ON clipboard.representations BEGIN
  INSERT INTO representations_FTS(representations_FTS, rowid, content) VALUES ('delete', OLD.id, OLD.content);

CREATE TRIGGER clipboard.representations_FTS_au AFTER UPDATE ON clipboard.representations BEGIN
  INSERT INTO representations_FTS(representations_FTS, content) VALUES ('delete', OLD.content);

CREATE TRIGGER clipboard.delete_item_representations
  AFTER DELETE ON items
  FOR EACH ROW
BEGIN
  DELETE FROM representations
  WHERE representations.item_id = OLD.id;
END;

CREATE TRIGGER clipboard.delete_entry_items
  AFTER DELETE ON entries
  FOR EACH ROW
BEGIN
  DELETE FROM items
  WHERE items.entry_id = OLD.id;
END;

CREATE TRIGGER clipboard.delete_entry_categories
  AFTER DELETE ON entries
  FOR EACH ROW
BEGIN
  DELETE FROM router_entry_category
  WHERE router_entry_category.entry_id = OLD.id;
END;

CREATE INDEX clipboard.representations_idx_entry_id_item_id ON representations(entry_id, item_id);

CREATE TRIGGER clipboard.delete_item_representations
  BEFORE DELETE ON items
  FOR EACH ROW
BEGIN
  DELETE FROM representations
  WHERE representations.item_id = OLD.id;
END;

CREATE TRIGGER clipboard.delete_entry_items
  BEFORE DELETE ON entries
  FOR EACH ROW
BEGIN
  DELETE FROM items
  WHERE items.entry_id = OLD.id;
END;

CREATE TRIGGER clipboard.representations_FTS_ai AFTER INSERT ON clipboard.representations BEGIN
  INSERT INTO representations_tri_FTS(rowid, content, entry_title)

CREATE TRIGGER clipboard.representations_FTS_ad BEFORE DELETE ON clipboard.representations BEGIN
  INSERT INTO representations_tri_FTS(representations_tri_FTS, rowid, content, entry_title)

CREATE TRIGGER clipboard.representations_FTS_au AFTER UPDATE ON clipboard.representations BEGIN
  INSERT INTO representations_tri_FTS(representations_tri_FTS, rowid, content, entry_title)

CREATE TABLE clipboard.filters (
    source_url TEXT PRIMARY KEY,
    enabled INTEGER NOT NULL DEFAULT 1
) STRICT, WITHOUT ROWID;

-- Map a filter (by source_url) to the tags it applies.
CREATE TABLE clipboard.router_filter_tag (
    source_url TEXT NOT NULL,
    tag TEXT NOT NULL,
    FOREIGN KEY (source_url) REFERENCES filters(source_url),
    PRIMARY KEY (source_url, tag)

CREATE INDEX clipboard.representations_idx_content_search
  ON representations(entry_id, content_search)

CREATE VIEW clipboard.representations_with_title AS SELECT id, content,
    (SELECT title FROM entries WHERE entries.id = representations.entry_id) AS entry_title FROM representations;

-- Create new FTS table based on representations with title using the
-- trigram tokenizer to enable substring search
CREATE VIRTUAL TABLE clipboard.representations_tri_FTS USING FTS5(
  content,
  entry_title,
  content='representations_with_title',
  content_rowid='id',
  tokenize='trigram'
);

CREATE TRIGGER clipboard.representations_tri_FTS_ai AFTER INSERT ON clipboard.representations BEGIN
  INSERT INTO representations_tri_FTS(rowid, content, entry_title)

CREATE TRIGGER clipboard.representations_tri_FTS_ad AFTER DELETE ON clipboard.representations BEGIN
  INSERT INTO representations_tri_FTS(representations_tri_FTS, rowid) VALUES ('delete', OLD.id);

CREATE TRIGGER clipboard.representations_tri_FTS_au AFTER UPDATE ON clipboard.representations BEGIN
  INSERT INTO representations_tri_FTS(representations_tri_FTS, content) VALUES ('delete', OLD.content);

CREATE TABLE clipboard.router_entry_tag (
    entry_id INTEGER NOT NULL,
    tag TEXT NOT NULL,
    FOREIGN KEY (entry_id) REFERENCES entries(id),
    PRIMARY KEY (entry_id, tag)

CREATE TRIGGER clipboard.update_entries_updated_at_on_tag_insert AFTER
INSERT ON router_entry_tag FOR EACH ROW
BEGIN
  UPDATE entries
  SET
    updated_at = CURRENT_TIMESTAMP
  WHERE
    id = NEW.entry_id;
END;

CREATE TRIGGER clipboard.update_entries_updated_at_on_tag_delete AFTER
DELETE ON router_entry_tag FOR EACH ROW
BEGIN
  UPDATE entries
  SET
    updated_at = CURRENT_TIMESTAMP
  WHERE
    id = OLD.entry_id;
END;

CREATE TRIGGER clipboard.delete_entry_tags
  AFTER DELETE ON entries
  FOR EACH ROW
BEGIN
  DELETE FROM router_entry_tag
  WHERE router_entry_tag.entry_id = OLD.id;
END;

CREATE INDEX clipboard.entries_idx_pinned ON entries(pinned);

CREATE INDEX clipboard.entries_idx_updated_at_id ON entries(updated_at DESC, id DESC);

CREATE INDEX clipboard.representations_idx_item_id ON representations(item_id);

CREATE TABLE screenshots.entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    path TEXT NOT NULL UNIQUE,
    category TEXT NOT NULL CHECK (category IN ('ScreenCapture', 'ScreenRecording')),
    text TEXT,
    is_pinned INTEGER NOT NULL DEFAULT 0,
    pin_order INTEGER,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    text_extracted_at TEXT
) STRICT;

CREATE INDEX screenshots.idx_screenshots_path ON entries(path);

CREATE INDEX screenshots.idx_screenshots_pinned ON entries(is_pinned, pin_order);

CREATE INDEX screenshots.idx_screenshots_modified ON entries(modified_at DESC);

CREATE TABLE user_activity.user_activity_new (
    id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
    activity_type TEXT NOT NULL,
    user_activity_info_key TEXT REFERENCES user_activity_info(key) ON DELETE SET NULL,
    platform TEXT NOT NULL,
    timezone_offset_minutes INTEGER NOT NULL DEFAULT 0,
    device TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE user_activity.ai_chat_activity_new (
    id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
    activity_type TEXT NOT NULL,
    source TEXT NOT NULL,
    chat_model TEXT NOT NULL,
    word_count INTEGER NOT NULL,
    timezone_offset_minutes INTEGER NOT NULL DEFAULT 0,
    device TEXT NOT NULL,
    platform TEXT NOT NULL DEFAULT '',
    updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE user_activity.user_focus_activity_new (
    id TEXT NOT NULL PRIMARY KEY DEFAULT(ULID()),
    source TEXT NOT NULL,
    date TEXT NOT NULL,
    duration REAL,
    pause_events TEXT,
    block_events TEXT,
    snooze_events TEXT,
    device TEXT NOT NULL,
    platform TEXT NOT NULL DEFAULT '',
    timezone_offset_minutes INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE user_activity.user_activity_info (
    key TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT(RAYDATE())

CREATE TABLE user_activity.user_activity (
    activity_type TEXT NOT NULL,
    user_activity_info_key TEXT REFERENCES user_activity_info(key) ON DELETE SET NULL,
    platform TEXT NOT NULL,
    timezone_offset_minutes INTEGER NOT NULL DEFAULT 0,
    device TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT(RAYDATE()),
    PRIMARY KEY (device, updated_at)

CREATE TABLE user_activity.ai_chat_activity (
    activity_type TEXT NOT NULL,
    source TEXT NOT NULL,
    chat_model TEXT NOT NULL,
    word_count INTEGER NOT NULL,
    timezone_offset_minutes INTEGER NOT NULL DEFAULT 0,
    device TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT(RAYDATE()),
    PRIMARY KEY (device, updated_at)

CREATE TABLE user_activity.user_focus_activity (
    source TEXT NOT NULL,
    date TEXT NOT NULL,
    duration REAL,
    pause_events TEXT,
    block_events TEXT,
    snooze_events TEXT,
    device TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT(RAYDATE()),
    PRIMARY KEY (device, updated_at)

CREATE TABLE node_extensions.tools (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    extension_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    icon TEXT,
    keywords TEXT, -- Stored as JSON array
    preferences TEXT, -- Stored as JSON array
    functionalities TEXT, -- Stored as JSON array
    confirmation INTEGER NOT NULL DEFAULT 0,
    input TEXT, -- Stored as JSON
    output TEXT, -- Stored as JSON
    instructions TEXT,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    digest TEXT, -- Stored as JSON
    FOREIGN KEY (extension_id) REFERENCES extensions(id) ON DELETE CASCADE
) STRICT;

CREATE TRIGGER node_extensions.update_tools_updated_at
AFTER UPDATE ON tools
FOR EACH ROW
BEGIN
  UPDATE tools
  SET updated_at = CURRENT_TIMESTAMP
  WHERE id = OLD.id;
END;

CREATE TABLE node_extensions.extensions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT,
    name TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    icon TEXT NOT NULL,
    keywords TEXT, -- Stored as JSON array
    license TEXT,
    author TEXT,
    owner TEXT,
    access TEXT,
    readme_url TEXT,
    source_url TEXT,
    ai TEXT, -- Stored as JSON
    preferences TEXT, -- Stored as JSON array
    local_sources TEXT,
    version TEXT,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    requires_download INTEGER NOT NULL DEFAULT 1
) STRICT;

CREATE TRIGGER node_extensions.update_extensions_updated_at
AFTER UPDATE ON extensions
FOR EACH ROW
BEGIN
  UPDATE extensions
  SET updated_at = CURRENT_TIMESTAMP
  WHERE id = OLD.id;
END;

CREATE TABLE node_extensions.commands (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    extension_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    title TEXT NOT NULL,
    subtitle TEXT,
    description TEXT NOT NULL,
    icon TEXT,
    keywords TEXT, -- Stored as JSON array
    mode TEXT NOT NULL,
    is_enabled INTEGER NOT NULL DEFAULT 1,
    preferences TEXT, -- Stored as JSON array
    arguments TEXT, -- Stored as JSON array
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    interval TEXT,
    ran_at TEXT,
    run_error TEXT,
    status_item TEXT, -- Stored as JSON
    interval_enabled INTEGER NOT NULL DEFAULT 0,
    custom_subtitle TEXT,
    assumed_view_kind TEXT,
    digest TEXT, -- Stored as JSON
    FOREIGN KEY (extension_id) REFERENCES extensions(id) ON DELETE CASCADE
) STRICT;

CREATE TRIGGER node_extensions.update_commands_updated_at
AFTER UPDATE ON commands
FOR EACH ROW
BEGIN
  UPDATE commands
  SET updated_at = CURRENT_TIMESTAMP
  WHERE id = OLD.id;
END;

CREATE INDEX node_extensions.idx_commands_extension_id ON commands(extension_id);

CREATE UNIQUE INDEX node_extensions.idx_extensions_extension_id ON extensions(extension_id);

CREATE UNIQUE INDEX node_extensions.idx_commands_extension_id_name ON commands(extension_id, name);

CREATE UNIQUE INDEX node_extensions.idx_tools_extension_id_name ON tools(extension_id, name);

CREATE TABLE node_extensions.widgets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  extension_id INTEGER NOT NULL REFERENCES extensions(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  icon TEXT,
  icon_variants TEXT CHECK (icon_variants IS NULL OR json_valid(icon_variants)),
  preferences TEXT CHECK (preferences IS NULL OR json_valid(preferences)),
  interval TEXT,
  digest TEXT CHECK (digest IS NULL OR json_valid(digest)),
  activated_at TEXT,
  preference_values TEXT CHECK (preference_values IS NULL OR json_valid(preference_values)),
  updated_at TEXT NOT NULL,
  UNIQUE (extension_id, name)

CREATE TABLE node_extensions.extension_install_history (
    extension_uuid TEXT PRIMARY KEY,
    first_installed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
) STRICT;

CREATE INDEX node_extensions.idx_extension_install_history_extension_uuid ON extension_install_history(extension_uuid);

CREATE TABLE IF NOT EXISTS %MIGRATION_TABLE_NAME%(
             version %VERSION_TYPE% PRIMARY KEY,
             name VARCHAR(255),
             applied_on VARCHAR(255),
             checksum VARCHAR(255));

CREATE TRIGGER IF NOT EXISTS entities_migration_guard_on_delete AFTER DELETE ON � BEGIN �] END;

CREATE TABLE IF NOT EXISTS %Q.'%q_stat'(id INTEGER PRIMARY KEY, value BLOB);