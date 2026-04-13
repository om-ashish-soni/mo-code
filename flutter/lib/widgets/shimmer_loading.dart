import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// A pulsing opacity animation for skeleton loading states.
class ShimmerLoading extends StatefulWidget {
  final Widget child;
  const ShimmerLoading({super.key, required this.child});

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: widget.child,
    );
  }
}

/// A single shimmer line placeholder.
class ShimmerLine extends StatelessWidget {
  final double width;
  final double height;
  const ShimmerLine({super.key, this.width = double.infinity, this.height = 12});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
    );
  }
}

/// Skeleton for a list item (icon + two lines).
class SkeletonListTile extends StatelessWidget {
  const SkeletonListTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerLine(width: MediaQuery.of(context).size.width * 0.5),
                const SizedBox(height: AppSpacing.sm),
                ShimmerLine(width: MediaQuery.of(context).size.width * 0.3, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton for a card with title + stats row.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerLine(height: 14),
          SizedBox(height: AppSpacing.md),
          Row(
            children: [
              ShimmerLine(width: 60, height: 10),
              SizedBox(width: AppSpacing.lg),
              ShimmerLine(width: 40, height: 10),
              Spacer(),
              ShimmerLine(width: 50, height: 10),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shows N skeleton list tiles with shimmer animation.
class SkeletonList extends StatelessWidget {
  final int itemCount;
  const SkeletonList({super.key, this.itemCount = 6});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Column(
        children: List.generate(itemCount, (_) => const SkeletonListTile()),
      ),
    );
  }
}

/// Shows N skeleton cards with shimmer animation.
class SkeletonCardList extends StatelessWidget {
  final int itemCount;
  const SkeletonCardList({super.key, this.itemCount = 5});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Column(
        children: List.generate(itemCount, (_) => const SkeletonCard()),
      ),
    );
  }
}
