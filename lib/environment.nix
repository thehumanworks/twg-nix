{ lib, cfg }:
lib.filterAttrs (_name: value: value != null) {
  TWG_SITE = cfg.site;
  TWG_USER = cfg.user;
  TWG_PROFILE = cfg.profile;
  TWG_CONFIG_DIR = cfg.configDir;
  TWG_CACHE_DIR = cfg.cacheDir;
  TWG_SKILLS_DIR = cfg.skillsDir;
  TWG_SECRET_STORE = cfg.secretStore;
  TWG_AGENT_DEFAULTS =
    if cfg.agentDefaults == null then
      null
    else if cfg.agentDefaults then
      "1"
    else
      "0";
}
