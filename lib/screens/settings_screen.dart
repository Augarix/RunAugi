import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../texty.dart';
import '../models/lang.dart';
import '../services/settings_service.dart' show SettingsService, MusicStyle;
import '../services/music_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final s = SettingsService.I;
  final nameCtrl = TextEditingController();

  // Label ~35 % řádku v intervalu 160–260 px
  static const double _labelColWidthMax = 260.0;
  static const double _labelColWidthMin = 160.0;

  // Jednotná minimální výška buněk
  static const double _rowMinHeight = 56.0;

  // Kompaktnější mřížka
  static const double _twoColsMinWidth = 660.0;
  static const double _cellGap = 6.0; // mezi buňkami

  final List<String> _characterIds = const ['augi'];
  int _charIndex = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
    nameCtrl.text = s.username;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(const AssetImage('assets/images/main_background.gif'), context);
    });
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    super.dispose();
  }

  void _onToggleVibration(bool v) { s.setVibration(v); setState(() {}); }
  void _onToggleMusic(bool v) async {
    s.setMusic(v);
    await MusicService.I.setEnabled(v);
    if (mounted) setState(() {});
  }

  Future<void> _onChangeMusicStyle(MusicStyle style) async {
    await s.setMusicStyle(style);
    await MusicService.I.ensureMenuMusic();
    if (mounted) setState(() {});
  }
  Future<void> _setLang(Lang lang) async {
    await s.setLang(lang);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final double panelWidth = (size.width * 0.92).clamp(520.0, 1100.0);

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: Text(T.settingsTitle(), style: const TextStyle(fontFamily: 'Augarix')),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
        automaticallyImplyLeading: false,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Stack(
              children: [
                Positioned.fill(child: Image.asset('assets/images/main_background.gif', fit: BoxFit.fill)),
                Positioned.fill(child: Container(color: Colors.black.withOpacity(0.35))),
              ],
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: panelWidth,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: LayoutBuilder(
                    builder: (context, cons) {
                      final w = cons.maxWidth;
                      final bool twoCols = w >= _twoColsMinWidth;
                      final double cardWidth = twoCols ? (w - _cellGap) / 2 : w;

                      final cards = <Widget>[
                        _row(T.settingsLanguage(), _LangSwitch(value: s.lang, onChanged: _setLang)),
                        _row(T.settingsUsername(), _usernameField()),
                        _row(T.settingsVibration(), Switch(value: s.vibrationOn, onChanged: _onToggleVibration)),
                        _row(T.settingsMusic(), Switch(value: s.musicOn, onChanged: _onToggleMusic)),
                        _row(T.musicStyle(), _MusicStyleSwitch(value: s.musicStyle, onChanged: _onChangeMusicStyle)),
                        _row(T.settingsCharacter(), _characterPickerCompact()),
                      ];

                      if (twoCols) {
                        return Wrap(
                          spacing: _cellGap,
                          runSpacing: _cellGap,
                          children: cards.map((c) => SizedBox(width: cardWidth, child: c)).toList(),
                        );
                      } else {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: cards
                              .map((c) => Padding(padding: const EdgeInsets.only(bottom: _cellGap), child: c))
                              .toList(),
                        );
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ————— UI helpers —————

  /// Řádek s adaptivní šířkou levého labelu (≈35 %, clamp 160–260 px) a kompaktními mezerami.
  Widget _row(String label, Widget right) {
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth;
        final labelW = (maxW * 0.35).clamp(_labelColWidthMin, _labelColWidthMax);

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 3),                 // menší okraj
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),// menší vnitřní okraj
          constraints: const BoxConstraints(minHeight: _rowMinHeight),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: labelW,
                child: Text(label,
                    style: const TextStyle(color: Colors.white70, fontFamily: 'Augarix'),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 12), // menší mezera mezi label/ovládáním
              Expanded(child: Align(alignment: Alignment.centerRight, child: right)),
            ],
          ),
        );
      },
    );
  }

  /// Username field – ~80 % pravé části, min 480 px, pokud je prostor.
  Widget _usernameField() {
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth.isFinite ? c.maxWidth : 0.0;
        double want = maxW * 1.10;
        if (maxW >= 480) {
          want = want < 480 ? 480 : want;
        }
        final box = maxW > 0
            ? ConstrainedBox(
          constraints: BoxConstraints.tightFor(width: want.clamp(0.0, maxW)),
          child: _usernameTextField(),
        )
            : _usernameTextField();
        return box;
      },
    );
  }

  Widget _usernameTextField() {
    return TextField(
      controller: nameCtrl,
      onSubmitted: (v) => setState(() => s.setUsername(v)),
      style: const TextStyle(color: Colors.white),
      decoration: const InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white12,
        border: OutlineInputBorder(),
      ),
    );
  }

  /// Kompaktní Character picker, aby výška držela 56 px.
  Widget _characterPickerCompact() {
    String assetFor(String id) => 'assets/images/augi.png';
    final id = _characterIds[_charIndex];

    const btnSize = 40.0;
    const preview = 48.0; // vejde se do řádku 56

    Widget arrow(IconData icon, VoidCallback onTap) {
      return InkResponse(
        onTap: onTap,
        radius: 24,
        child: Container(
          width: btnSize,
          height: btnSize,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.25),
            borderRadius: BorderRadius.circular(btnSize / 2),
            border: Border.all(color: Colors.white30),
          ),
          child: Icon(icon, color: Colors.white),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        arrow(Icons.chevron_left, _prevCharacter),
        const SizedBox(width: 8),
        Container(
          width: preview,
          height: preview,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.25),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white24),
          ),
          child: Image.asset(assetFor(id), fit: BoxFit.contain),
        ),
        const SizedBox(width: 8),
        arrow(Icons.chevron_right, _nextCharacter),
      ],
    );
  }

  void _prevCharacter() {
    setState(() {
      _charIndex = (_charIndex - 1) % _characterIds.length;
      if (_charIndex < 0) _charIndex = _characterIds.length - 1;
      s.setCharacterId(_characterIds[_charIndex]);
    });
  }

  void _nextCharacter() {
    setState(() {
      _charIndex = (_charIndex + 1) % _characterIds.length;
      s.setCharacterId(_characterIds[_charIndex]);
    });
  }
}

// ——— Velký (kompaktní) Segmented přepínač hudebního stylu ———
class _MusicStyleSwitch extends StatelessWidget {
  final MusicStyle value;
  final ValueChanged<MusicStyle> onChanged;
  const _MusicStyleSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final total = c.maxWidth.isFinite ? c.maxWidth : 0.0;
        final computed = total > 0 ? (total - 12) / 2 : 160.0;
        final segW = computed < 160 ? 160.0 : computed;
        const segH = 44.0; // kompaktnější, aby seděl do řádku 56

        return SizedBox(
          height: segH,
          child: SegmentedButton<MusicStyle>(
            segments: [
              ButtonSegment(
                value: MusicStyle.traditional,
                label: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(T.musicStyleTraditional(), softWrap: false, overflow: TextOverflow.fade),
                ),
              ),
              ButtonSegment(
                value: MusicStyle.modern,
                label: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(T.musicStyleModern(), softWrap: false, overflow: TextOverflow.fade),
                ),
              ),
            ],
            selected: {value},
            showSelectedIcon: false,
            style: ButtonStyle(
              minimumSize: MaterialStatePropertyAll(Size(segW, segH)),
              padding: const MaterialStatePropertyAll(EdgeInsets.zero),
              side: MaterialStateProperty.resolveWith((states) {
                final sel = states.contains(MaterialState.selected);
                return BorderSide(color: Colors.white.withOpacity(sel ? 0.75 : 0.35), width: sel ? 2 : 1);
              }),
              textStyle: const MaterialStatePropertyAll(
                TextStyle(fontSize: 18, height: 1.2, fontFamily: 'Augarix', letterSpacing: 0.5),
              ),
              backgroundColor: MaterialStateProperty.resolveWith(
                    (states) => states.contains(MaterialState.selected)
                    ? Colors.white.withOpacity(0.18)
                    : Colors.white.withOpacity(0.10),
              ),
              foregroundColor: const MaterialStatePropertyAll(Colors.white),
              shape: MaterialStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              ),
            ),
            onSelectionChanged: (set) { if (set.isNotEmpty) onChanged(set.first); },
          ),
        );
      },
    );
  }
}

// ——— Stejný kompaktní přepínač pro jazyk (CZ/EN) ———
class _LangSwitch extends StatelessWidget {
  final Lang value;
  final ValueChanged<Lang> onChanged;
  const _LangSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final total = c.maxWidth.isFinite ? c.maxWidth : 0.0;
        final computed = total > 0 ? (total - 12) / 2 : 160.0;
        final segW = computed < 160 ? 160.0 : computed;
        const segH = 44.0;

        return SizedBox(
          height: segH,
          child: SegmentedButton<Lang>(
            segments: const [
              ButtonSegment(
                value: Lang.cz,
                label: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text('CZ', softWrap: false, overflow: TextOverflow.fade),
                ),
              ),
              ButtonSegment(
                value: Lang.en,
                label: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text('EN', softWrap: false, overflow: TextOverflow.fade),
                ),
              ),
            ],
            selected: {value},
            showSelectedIcon: false,
            style: ButtonStyle(
              minimumSize: MaterialStatePropertyAll(Size(segW, segH)),
              padding: const MaterialStatePropertyAll(EdgeInsets.zero),
              side: MaterialStateProperty.resolveWith((states) {
                final sel = states.contains(MaterialState.selected);
                return BorderSide(color: Colors.white.withOpacity(sel ? 0.75 : 0.35), width: sel ? 2 : 1);
              }),
              textStyle: const MaterialStatePropertyAll(
                TextStyle(fontSize: 18, height: 1.2, fontFamily: 'Augarix', letterSpacing: 0.5),
              ),
              backgroundColor: MaterialStateProperty.resolveWith(
                    (states) => states.contains(MaterialState.selected)
                    ? Colors.white.withOpacity(0.18)
                    : Colors.white.withOpacity(0.10),
              ),
              foregroundColor: const MaterialStatePropertyAll(Colors.white),
              shape: MaterialStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              ),
            ),
            onSelectionChanged: (set) { if (set.isNotEmpty) onChanged(set.first); },
          ),
        );
      },
    );
  }
}
