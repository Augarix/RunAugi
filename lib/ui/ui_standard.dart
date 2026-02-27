import 'package:flutter/material.dart';

/// ---- UI STANDARD: konstanty a znovupoužitelné widgety ----
class UiStd {
  // Layout
  static const twoColsMinWidth = 660.0; // breakpoint
  static const cellGap = 6.0;           // mezera mezi buňkami
  static const rowMinHeight = 56.0;     // jednotná výška buněk
  static const labelMin = 160.0;        // label ~35% (clamp)
  static const labelMax = 260.0;

  // Styl buněk (panelů)
  static BoxDecoration cellDecoration(BuildContext _) => BoxDecoration(
    color: Colors.white.withOpacity(0.06),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: Colors.white24),
  );

  static const cellPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 8);
  static const cellMargin  = EdgeInsets.symmetric(vertical: 3);

  /// Jednotný řádek nastavení (label vlevo, prvek vpravo)
  static Widget row({
    required String label,
    required Widget trailing,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth;
        final labelW = (maxW * 0.35).clamp(labelMin, labelMax);
        return Container(
          margin: cellMargin,
          padding: cellPadding,
          constraints: const BoxConstraints(minHeight: rowMinHeight),
          decoration: cellDecoration(context),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: labelW,
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white70, fontFamily: 'Augarix'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Align(alignment: Alignment.centerRight, child: trailing)),
            ],
          ),
        );
      },
    );
  }

  /// Kompaktní SegmentedButton – sedí do řádku 56 px (výška 44)
  static Widget segmented<T>({
    required List<(T value, String label)> options,
    required T selected,
    required ValueChanged<T> onChanged,
  }) {
    const segH = 44.0;
    return LayoutBuilder(
      builder: (context, c) {
        final total = c.maxWidth.isFinite ? c.maxWidth : 0.0;
        final computed = total > 0 ? (total - 12) / (options.length) : 160.0;
        final segW = computed < 160 ? 160.0 : computed;

        return SizedBox(
          height: segH,
          child: SegmentedButton<T>(
            segments: [
              for (final o in options)
                ButtonSegment<T>(
                  value: o.$1,
                  label: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text(o.$2, softWrap: false, overflow: TextOverflow.fade),
                  ),
                ),
            ],
            selected: {selected},
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
            onSelectionChanged: (set) {
              if (set.isNotEmpty) onChanged(set.first);
            },
          ),
        );
      },
    );
  }

  /// Kompaktní character picker (48 px náhled, 40 px šipky) – drží řádek 56 px
  static Widget characterPicker({
    required String imagePath,
    required VoidCallback onPrev,
    required VoidCallback onNext,
  }) {
    const btnSize = 40.0;
    const preview = 48.0;

    Widget arrow(IconData icon, VoidCallback onTap) => InkResponse(
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

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        arrow(Icons.chevron_left, onPrev),
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
          child: Image.asset(imagePath, fit: BoxFit.contain),
        ),
        const SizedBox(width: 8),
        arrow(Icons.chevron_right, onNext),
      ],
    );
  }
}
