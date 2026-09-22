import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import 'settings_tile.dart';

/// A labelled section with a rounded bordered card containing [SettingsTile]s
/// separated by 1-px dividers.
///
/// Spec:
/// - Section label: 13 / w600 / muted, sentence case. Padding left 4 / bottom 8.
///   Top padding: 4 for first label, 20 for subsequent.
/// - Card: border 1px line, radius 22, clipBehavior antiAlias, bg color.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.label,
    required this.tiles,
    this.isFirst = false,
  });

  final String label;
  final List<SettingsTile> tiles;

  /// When [isFirst] is true, top padding is 4; otherwise 20.
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final c = context.nearhoodColors;

    return Padding(
      padding: EdgeInsets.only(top: isFirst ? 4 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section label
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.muted,
              ),
            ),
          ),

          // Rounded card
          Container(
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: c.line, width: 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < tiles.length; i++) ...[
                  tiles[i],
                  if (i < tiles.length - 1)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: c.line,
                      indent: 0,
                      endIndent: 0,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
