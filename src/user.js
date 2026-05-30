/****************************************************************************
 * FIREFOX USER.JS - BALANCED POWER USER PROFILE                           *
 * Optimized for: Performance + Privacy + Stability + Daily Use            *
 * Updated: 2026                                                            *
 ****************************************************************************/

/****************************************************************************
 * 1. DEVTOOLS & UI/UX TWEAKS                                              *
 ****************************************************************************/

/* Enable advanced DevTools */
user_pref("devtools.chrome.enabled", true);
user_pref("devtools.debugger.remote-enabled", true);
user_pref("devtools.debugger.prompt-connection", false);

/* Enable userChrome.css / userContent.css */
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
user_pref("svg.context-properties.content.enabled", true);

/* UI tweaks */
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.compactmode.show", true);
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.menu.showViewImageInfo", true);
user_pref("browser.tabs.tabMinWidth", 125);
user_pref("browser.tabs.delayHidingAudioPlayingIconMS", 0);
user_pref("findbar.highlightAll", true);
user_pref("layout.word_select.eat_space_to_next_word", false);
user_pref("ui.key.menuAccessKeyFocuses", false);

/* Linux GTK fixes */
user_pref("widget.gtk.rounded-bottom-corners.enabled", true);
user_pref("widget.gtk.ignore-bogus-leave-notify", 1);

/* Enable PWA */
user_pref("browser.taskbarTabs.enabled", true);

/****************************************************************************
 * 2. URLBAR, SEARCH & NEW TAB CLEANUP                                     *
 ****************************************************************************/

/* Cleaner URL bar */
user_pref("browser.urlbar.suggest.engines", false);
user_pref("browser.urlbar.suggest.topsites", false);
user_pref("browser.urlbar.suggest.openpage", false);
user_pref("browser.urlbar.suggest.bookmark", false);
user_pref("browser.urlbar.suggest.quickactions", false);

user_pref("browser.urlbar.suggest.history", true);
user_pref("browser.urlbar.suggest.searches", true);

/* URL cleanup */
user_pref("browser.urlbar.trimHttps", true);
user_pref("browser.urlbar.trimURLs", true);

/* Disable sponsored content */
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);

/* Open PDFs inside Firefox */
user_pref("browser.download.open_pdf_attachments_inline", true);

/****************************************************************************
 * 3. PERFORMANCE                                                          *
 ****************************************************************************/

/* Enable modern GPU rendering */
user_pref("gfx.webrender.all", true);

/* Better tab memory handling */
user_pref("browser.tabs.unloadOnLowMemory", true);

/* DNS cache */
user_pref("network.dnsCacheExpiration", 3600);

/* HTTP connection tuning */
user_pref("network.http.max-persistent-connections-per-server", 10);

/****************************************************************************
 * 4. SMOOTH SCROLLING (SMOOTHFOX)                                         *
 ****************************************************************************/

user_pref("apz.overscroll.enabled", true);

user_pref("general.smoothScroll", true);
user_pref("general.smoothScroll.msdPhysics.enabled", true);

user_pref("general.smoothScroll.msdPhysics.continuousMotionMaxDeltaMS", 12);
user_pref("general.smoothScroll.msdPhysics.motionBeginSpringConstant", 600);
user_pref("general.smoothScroll.msdPhysics.regularSpringConstant", 650);

user_pref("general.smoothScroll.msdPhysics.slowdownMinDeltaMS", 25);
user_pref("general.smoothScroll.msdPhysics.slowdownMinDeltaRatio", "2");
user_pref("general.smoothScroll.msdPhysics.slowdownSpringConstant", 250);

user_pref("general.smoothScroll.currentVelocityWeighting", "1");
user_pref("general.smoothScroll.stopDecelerationWeighting", "1");

/* Mouse wheel sensitivity */
user_pref("mousewheel.default.delta_multiplier_y", 250);

/****************************************************************************
 * 5. PRIVACY & SECURITY                                                   *
 ****************************************************************************/

/* Global Privacy Control */
user_pref("privacy.globalprivacycontrol.enabled", true);

/* Firefox Containers */
user_pref("privacy.userContext.enabled", true);

/* Block notification spam */
user_pref("permissions.default.desktop-notification", 2);

/* Block geolocation requests */
user_pref("permissions.default.geo", 2);

/* Better geolocation provider */
user_pref("geo.provider.network.url", "https://beacondb.net/v1/geolocate");

/* WebRTC enabled but reduce IP leakage */
user_pref("media.peerconnection.enabled", true);
user_pref("media.peerconnection.ice.no_host", true);

/* Mixed content protection */
user_pref("security.mixed_content.block_display_content", true);

/* Disable 0-RTT TLS */
user_pref("security.tls.enable_0rtt_data", false);

/****************************************************************************
 * 6. TELEMETRY & EXPERIMENTS                                              *
 ****************************************************************************/

/* Disable telemetry */
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.healthreport.uploadEnabled", false);

user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.archive.enabled", false);

/* Disable studies */
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("app.normandy.enabled", false);

/* Disable crash report submission */
user_pref("browser.tabs.crashReporting.sendReport", false);

/****************************************************************************
 * 7. SESSION & STABILITY                                                  *
 ****************************************************************************/

/* Restore previous session */
user_pref("browser.startup.page", 3);

/* Session save interval */
user_pref("browser.sessionstore.interval", 60000);

/* Limit recently closed tabs memory usage */
user_pref("browser.sessionstore.max_tabs_undo", 5);
