import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.label,
    required this.tiles,
    this.isFirst = false,
  });

  final String label;
  final List<Widget> tiles;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: isFirst ? 4 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.divider, width: 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < tiles.length; i++) ...[
                  tiles[i],
                  if (i < tiles.length - 1)
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.divider,
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
