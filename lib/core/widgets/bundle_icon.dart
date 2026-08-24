import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';

/// A rendered macOS icon, with a token-coloured placeholder until it arrives.
///
/// Takes bytes rather than a model so anything with an icon can use it — an
/// installed app, the app behind a launch agent, a running process. `AppIcon`
/// in the applications feature does the same job for a `MacApp`; this is the
/// shape for everywhere else.
class BundleIcon extends StatelessWidget {
  const BundleIcon({
    super.key,
    required this.bytes,
    this.size = 32,
    this.fallback = AppIcons.appPlaceholder,
    this.fallbackColor,
  });

  final Uint8List? bytes;
  final double size;
  final IconData fallback;
  final Color? fallbackColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final placeholder = Icon(
      fallback,
      size: size * 0.55,
      color: fallbackColor ?? colors.textMuted,
    );

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: AppRadii.smAll,
        color: colors.surfaceRaised,
      ),
      child: bytes == null
          ? placeholder
          : ClipRRect(
              borderRadius: AppRadii.smAll,
              child: Image.memory(
                bytes!,
                fit: BoxFit.cover,
                // A corrupt or half-written icon must not take the row with it.
                errorBuilder: (_, _, _) => placeholder,
              ),
            ),
    );
  }
}
