import 'package:flutter/material.dart';
import '../texty.dart';
import '../models/lang.dart';
import '../services/settings_service.dart' show SettingsService, MusicStyle;
import '../services/music_service.dart';

// UI standard – stejné pomocné prvky jako v hlavních Settings
import '../ui/ui_standard.dart';

typedef IngameAction = void Function(IngameCommand cmd);
enum IngameCommand { menu, newRun, changeMode, resetSeed }

class IngameSettingsModal extends StatefulWidget {
  final IngameAction onAction;
  const IngameSettingsModal({super.key, required this.onAction});

  @override
  State<IngameSettingsModal> createState() => _IngameSettingsModalState();
}

class _IngameSettingsModalState extends State<IngameSettingsModal> {
  final s = SettingsService.I;

  final List<String> _characterIds = const ['augi'];
  int _charIndex = 0;

  // Nižší breakpoint pro dvousloupcové rozložení v modalu
  static const double _modalTwoColsMinWidth = 520.0;

  @override
  void initState() {
    super.initState();
    s.addListener(_onSettingsChanged);

    final saved = s.characterId;
    if (saved != null) {
      final i = _characterIds.indexOf(saved);
      if (i >= 0) _charIndex = i;
    }
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    s.removeListener(_onSettingsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isLandscape = size.width > size.height;
    final base = isLandscape ? size.height * 0.85 : size.width * 0.90;
    final panelWidth = base.clamp(520.0, size.width * 0.98);
    final maxPanelHeight = size.height * 0.80;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxPanelHeight),
        child: SizedBox(
          width: panelWidth,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.90),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 24, spreadRadius: 2),
                ],
              ),
              child: SingleChildScrollView(
                child: LayoutBuilder(
                  builder: (context, cons) {
                    final w = cons.maxWidth;
                    final twoCols = w >= _modalTwoColsMinWidth;
                    final colW = twoCols ? (w - UiStd.cellGap) / 2 : w;

                    final cards = <Widget>[
                      // Jazyk: shodné chování – jednoduchý CZ/EN segmented (bez textací)
                      UiStd.row(
                        label: T.settingsLanguage(),
                        trailing: UiStd.segmented<Lang>(
                          options: const [(Lang.cz, 'CZ'), (Lang.en, 'EN')],
                          selected: s.lang,
                          onChanged: (v) async {
                            await s.setLang(v);
                            if (mounted) setState(() {});
                          },
                        ),
                      ),

                      // Vibrace
                      UiStd.row(
                        label: T.settingsVibration(),
                        trailing: Switch(
                          value: s.vibrationOn,
                          onChanged: (v) async => await s.setVibration(v),
                        ),
                      ),

                      // Hudba on/off – ve hře nespouštět menu hudbu
                      UiStd.row(
                        label: T.settingsMusic(),
                        trailing: Switch(
                          value: s.musicOn,
                          onChanged: (v) async {
                            await s.setMusic(v);
                            if (v) {
                              await MusicService.I.setEnabled(true, startMenuIfOn: false);
                              await MusicService.I.stopMenuMusic();
                              await MusicService.I.playGameTrackForLockedSeed();
                            } else {
                              await MusicService.I.setEnabled(false);
                            }
                          },
                        ),
                      ),

                      // Styl hudby – stejné segmenty jako v hlavních Settings
                      UiStd.row(
                        label: T.musicStyle(),
                        trailing: UiStd.segmented<MusicStyle>(
                          options: [
                            (MusicStyle.traditional, T.musicStyleTraditional()),
                            (MusicStyle.modern,      T.musicStyleModern()),
                          ],
                          selected: s.musicStyle,
                          onChanged: (style) async {
                            await s.setMusicStyle(style);
                            await MusicService.I.applyStyleNow(playInGame: true);
                            if (mounted) setState(() {});
                          },
                        ),
                      ),

                      // Výběr postavy – kompaktní picker
                      UiStd.row(
                        label: T.settingsCharacter(),
                        trailing: UiStd.characterPicker(
                          imagePath: _assetFor(_characterIds[_charIndex]),
                          onPrev: _prevCharacter,
                          onNext: _nextCharacter,
                        ),
                      ),



                      // Akce
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          _actionBtn(T.backToMenu(), () => widget.onAction(IngameCommand.menu)),
                          _actionBtn(T.newRun(), () => widget.onAction(IngameCommand.newRun)),
                          _actionBtn(T.changeMode(), () => widget.onAction(IngameCommand.changeMode)),
                          _actionBtnWithIcon(
                            T.resetSeed(),
                            'assets/images/placeholder.png',
                                () => widget.onAction(IngameCommand.resetSeed),
                          ),
                        ],
                      ),
                    ];

                    if (twoCols) {
                      return Wrap(
                        spacing: UiStd.cellGap,
                        runSpacing: UiStd.cellGap,
                        children: cards.map((c) => SizedBox(width: colW, child: c)).toList(),
                      );
                    } else {
                      return Column(
                        children: [
                          for (final c in cards)
                            Padding(padding: const EdgeInsets.only(bottom: UiStd.cellGap), child: c),
                        ],
                      );
                    }
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // —— helpers ——
  String _assetFor(String id) {
    // ✔️ opravena case-sensitive cesta
    switch (id) {
      case 'augi':
      default:
        return 'assets/images/augi.png';
    }
  }

  void _prevCharacter() {
    setState(() {
      _charIndex = (_charIndex - 1) % _characterIds.length;
      if (_charIndex < 0) _charIndex = _characterIds.length - 1;
      SettingsService.I.setCharacterId(_characterIds[_charIndex]);
    });
  }

  void _nextCharacter() {
    setState(() {
      _charIndex = (_charIndex + 1) % _characterIds.length;
      SettingsService.I.setCharacterId(_characterIds[_charIndex]);
    });
  }

  Widget _actionBtn(String label, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white.withOpacity(0.10),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: Colors.white.withOpacity(0.35)),
      ),
      child: Text(label, style: const TextStyle(fontFamily: 'Augarix')),
    );
  }

  Widget _actionBtnWithIcon(String label, String assetPath, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white.withOpacity(0.10),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: Colors.white.withOpacity(0.35)),
      ),
      icon: Image.asset(assetPath, width: 18, height: 18, color: Colors.white70),
      label: Text(label, style: const TextStyle(fontFamily: 'Augarix')),
    );
  }
}
