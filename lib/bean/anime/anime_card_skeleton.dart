import 'package:flutter/material.dart';

/// Placeholder list shaped like [AnimeInfoCard]s, with Telegram's shimmer: a
/// soft highlight band sweeping across the placeholder shapes every 1.3 s
/// (ease-out), so loading reads as "content is coming" rather than a spinner.
class AnimeCardSkeletonList extends StatefulWidget {
  const AnimeCardSkeletonList({super.key, this.count = 8});

  final int count;

  @override
  State<AnimeCardSkeletonList> createState() => _AnimeCardSkeletonListState();
}

class _AnimeCardSkeletonListState extends State<AnimeCardSkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color base = scheme.onSurface.withValues(alpha: 0.08);
    final Color highlight = scheme.onSurface.withValues(alpha: 0.16);
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, child) {
        final double t = Curves.easeOut.transform(_shimmer.value);
        return ShaderMask(
          // srcIn paints the gradient exactly where the shapes are.
          blendMode: BlendMode.srcIn,
          shaderCallback: (Rect bounds) {
            // The band travels from fully left of the list to fully right.
            final double x = -1.5 + 3.0 * t;
            return LinearGradient(
              begin: Alignment(x - 0.6, -0.3),
              end: Alignment(x + 0.6, 0.3),
              colors: [base, highlight, base],
              stops: const [0, 0.5, 1],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: Column(
        children: [
          for (int i = 0; i < widget.count; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SkeletonCard(seed: i),
            ),
        ],
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.seed});

  final int seed;

  Widget _bar(double width, double height, {double radius = 4}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Vary the title length a little so the list does not look stamped out.
    final double titleWidth = 140.0 + (seed * 53 % 120);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bar(titleWidth, 16),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _bar(64, 26, radius: 8),
                    const SizedBox(width: 8),
                    _bar(84, 26, radius: 8),
                    const SizedBox(width: 8),
                    _bar(48, 26, radius: 8),
                  ],
                ),
              ],
            ),
          ),
          _bar(24, 24, radius: 12),
        ],
      ),
    );
  }
}
