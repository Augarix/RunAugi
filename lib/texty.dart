// Centralizované texty CZ/EN
import 'models/lang.dart'; // ← používáme jednotný Lang

class T {
  static Lang lang = Lang.cz;
  static String _t(String cz, String en) => lang == Lang.cz ? cz : en;

  // App
  static String appTitle() => _t('AugiRun', 'AugiRun');

  // Main Menu
  static String btnRun() => _t('RUN!', 'RUN!');
  static String btnSettings() => _t('Nastavení', 'Settings');
  static String btnLeaderboard() => _t('Žebříček', 'Leaderboard');
  static String btnAchievements() => _t('Achievementy', 'Achievements');
  static String version(String v) => _t('Verze ', 'Version ') + v;

  // Settings
  static String settingsTitle() => _t('Nastavení', 'Settings');
  static String settingsLanguage() => _t('Jazyk', 'Language');
  static String settingsLanguageCZ() => _t('Čeština', 'Czech');
  static String settingsLanguageEN() => _t('Angličtina', 'English');
  static String settingsUsername() => _t('Uživatelské jméno', 'Username');
  static String settingsVibration() => _t('Vibrace', 'Vibration');
  static String settingsMusic() => _t('Hudba', 'Music');
  static String settingsCharacter() => _t('Výběr postavy', 'Character select');
  static String comingSoon() => _t('Již brzy', 'Coming soon');

  // Music style
  static String musicStyle() => _t('Styl hudby', 'Music style');
  static String musicStyleTraditional() => _t('Tradiční', 'Classic');
  static String musicStyleModern() => _t('Moderní', 'Modern');

  // Run select
  static String selectMode() => _t('Vyber obtížnost', 'Select Mode');
  static String modeEasy() => _t('SNADNÁ', 'EASY');
  static String modeMedium() => _t('STŘEDNÍ', 'MEDIUM');
  static String modeHard() => _t('TĚŽKÁ', 'HARD');
  static String modeEndless() => _t('NEKONEČNÁ', 'ENDLESS');

  // Leaderboard
  static String leaderboardTitle() => _t('Žebříček', 'Leaderboard');
  static String miles() => _t('km', 'miles');
  static String division() => _t('Divize ', 'Division ');

  // Achievements
  static String achievementsTitle() => _t('Denní úspěchy', 'Daily Achievements');
  static String adExtra() => _t('Odemknout 2 navíc (reklama)', 'Unlock 2 extra (ad)');
  static String restartOne() => _t('Restart jednoho (reklama)', 'Restart one (ad)');

  // Ingame
  static String ingameSettings() => _t('In-game Nastavení', 'In-game Settings');
  static String resetSeed() => _t('Reset seedu', 'Reset seed');
  static String resetSeedInfo() => _t(
    'Resetem seedu nedostaneš body za dokončení.',
    'Resetting the seed won’t grant completion points.',
  );
  static String backToMenu() => _t('Menu', 'Menu');
  static String newRun() => _t('Nová hra', 'New run');
  static String changeMode() => _t('Změnit obtížnost', 'Change mode');

  // Game flow
  static String congrats() => _t('Gratulace!', 'Congratulations!');
  static String finished() => _t('Dokončeno.', 'Finished.');
  static String death() => _t('Au! Smrt.', 'Ouch! Death.');

  // Loading/Generating
  static String generating() => _t('Generuji...', 'Generating...');
}
