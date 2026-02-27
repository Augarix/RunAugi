import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../texty.dart';
import '../models/leaderboard_model.dart';
import '../models/player_prefs.dart';
import '../services/settings_service.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  bool _scrolledToPlayer = false;
  late final SettingsService _settings;
  String? _prevName;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse; // 0..1

  static const double _rowExtent = 57.0; // výška řádku (tile + divider)

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(const AssetImage('assets/images/main_background.gif'), context);
    });

    _settings = SettingsService.I;
    _prevName = _settings.username;

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);

    _ensurePlayerInLeaderboard(_settings.username, triggerRebuild: true);
    _settings.addListener(_onSettingsChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToPlayerCentered());
  }

  void _onSettingsChanged() {
    final newName = _settings.username;
    if (newName != _prevName) {
      _prevName = newName;
      _scrolledToPlayer = false;
    }
    _ensurePlayerInLeaderboard(newName, triggerRebuild: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToPlayerCentered());
  }

  void _ensurePlayerInLeaderboard(String playerName, {bool triggerRebuild = false}) {
    final name = playerName.trim();
    if (name.isEmpty) return;

    final currentMiles = PlayerProfile.I.milesTotal;
    final exists = LeaderboardModel.I.entries.any((e) => e.name == name);

    if (!exists) {
      LeaderboardModel.I.updatePlayer(name, 0);
    } else {
      LeaderboardModel.I.updatePlayer(name, currentMiles);
    }

    if (triggerRebuild && mounted) setState(() {});
  }

  void _scrollToPlayerCentered() {
    if (_scrolledToPlayer || !_scroll.hasClients) return;

    final playerName = _settings.username;
    final lb = LeaderboardModel.I.entries;
    final index = lb.indexWhere((e) => e.name == playerName);
    if (index < 0) return;

    final viewport = _scroll.position.viewportDimension;
    final centeredOffset = (index * _rowExtent) - (viewport / 2 - _rowExtent / 2);
    final maxOff = _scroll.position.maxScrollExtent;
    _scroll.jumpTo(centeredOffset.clamp(0.0, maxOff));
    _scrolledToPlayer = true;
  }

  @override
  Widget build(BuildContext context) {
    final lb = LeaderboardModel.I.entries;
    final div = PlayerProfile.I.randomDivisionHex;
    final playerName = _settings.username;

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: Colors.black, // pod GIFem
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          title: Text(T.leaderboardTitle(), style: const TextStyle(fontFamily: 'Augarix')),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
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
            // 🔁 stejné full-bleed pozadí jako v MainMenu (fit: fill)
            Positioned.fill(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: SizedBox.expand(
                      child: Image.asset(
                        'assets/images/main_background.gif',
                        fit: BoxFit.fill,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Container(color: Colors.black.withOpacity(0.35)),
                  ),
                ],
              ),
            ),

            // obsah
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = MediaQuery.of(context).size;
                  final tableWidth = (size.width * 0.75).clamp(360.0, size.width * 0.98);

                  const topGap = 24.0;
                  final availableListHeight =
                  (constraints.maxHeight - topGap).clamp(160.0, constraints.maxHeight);

                  return Stack(
                    children: [
                      Positioned(
                        right: 16,
                        top: 8,
                        child: Text(
                          '${T.division()}#${div.substring(0, 4)}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontFamily: 'Augarix',
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.center,
                        child: SizedBox(
                          width: tableWidth,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: topGap),
                              Container(
                                height: availableListHeight.toDouble(),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: AnimatedBuilder(
                                  animation: _pulse,
                                  builder: (_, __) {
                                    final pulse = _pulse.value;
                                    final borderOpacity = 0.6 + 0.4 * pulse;
                                    final glowBlur = 4.0 + 6.0 * pulse;
                                    final glowOpacity = 0.12 + 0.18 * pulse;

                                    return ListView.separated(
                                      controller: _scroll,
                                      itemCount: lb.length,
                                      separatorBuilder: (_, __) =>
                                      const Divider(color: Colors.white12, height: 1),
                                      itemBuilder: (_, i) {
                                        final e = lb[i];
                                        final isPlayer = e.name == playerName;

                                        final decoration = BoxDecoration(
                                          color: isPlayer
                                              ? Colors.white.withOpacity(0.06)
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(10),
                                          border: isPlayer
                                              ? Border.all(
                                            color: Colors.white.withOpacity(borderOpacity),
                                            width: 2,
                                          )
                                              : null,
                                          boxShadow: isPlayer
                                              ? [
                                            BoxShadow(
                                              color: Colors.white.withOpacity(glowOpacity),
                                              blurRadius: glowBlur,
                                              spreadRadius: 1,
                                            ),
                                          ]
                                              : null,
                                        );

                                        return SizedBox(
                                          height: _rowExtent,
                                          child: Container(
                                            decoration: decoration,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 12,
                                            ),
                                            child: Row(
                                              children: [
                                                SizedBox(
                                                  width: 56,
                                                  child: Text(
                                                    '#${i + 1}',
                                                    style: const TextStyle(
                                                      color: Colors.white54,
                                                      fontFamily: 'Augarix',
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: Text(
                                                    e.name,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontFamily: 'Augarix',
                                                    ),
                                                  ),
                                                ),
                                                SizedBox(
                                                  width: 100,
                                                  child: Text(
                                                    '${e.miles} ${T.miles()}',
                                                    textAlign: TextAlign.right,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Colors.white70,
                                                      fontFamily: 'Augarix',
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    _scroll.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }
}
