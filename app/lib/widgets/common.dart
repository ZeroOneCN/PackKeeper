import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:styled_widget/styled_widget.dart';

import '../core/models.dart';
import '../core/theme.dart';

/// 卡片圆角半径。
const double kCardRadius = 14;

/// 左滑操作卡片。
///
/// 把 [Slidable] 包进卡片圆角内，动作按钮被同一套圆角与外框裁剪，
/// 视觉上属于卡片本身，而不是卡片外侧单独的一块。
///
/// 参数：[slideKey] 滑动项主键；[groupTag] 同一列表的自动收起分组；
/// [extentRatio] 动作区占卡片宽度的比例；[actions] 动作按钮列表；
/// [child] 卡片内容（通常是 [AppCard]）。
class SlideActionCard extends StatelessWidget {
  const SlideActionCard({
    super.key,
    required this.slideKey,
    required this.groupTag,
    required this.extentRatio,
    required this.actions,
    required this.child,
  });

  final Key slideKey;
  final String groupTag;
  final double extentRatio;
  final List<Widget> actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(color: AppColors.line),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kCardRadius),
        child: Slidable(
          key: slideKey,
          groupTag: groupTag,
          endActionPane: ActionPane(
            motion: const ScrollMotion(),
            extentRatio: extentRatio,
            children: actions,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 统一的白色圆角卡片。
///
/// 参数：[child] 卡片内容；[padding] 内边距；[onTap] 点击回调；
/// [color] 背景色；[borderColor] 边框色；[seamless] 为 true 时不裁圆角、
/// 不画边框，由外层 [SlideActionCard] 统一裁剪，避免左滑时卡片与动作
/// 按钮之间出现弧形缝隙。
/// 返回：链式构造的圆角卡片（可点击时带水波纹）。
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.borderColor,
    this.seamless = false,
  }) : contentPadding = padding;

  final Widget child;

  /// 内容内边距（字段名避开 `padding` 扩展方法，便于链式调用）。
  final EdgeInsetsGeometry contentPadding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;

  /// 是否交给外层统一裁剪（左滑卡片内使用）。
  final bool seamless;

  @override
  Widget build(BuildContext context) {
    final inset = contentPadding.resolve(Directionality.of(context));
    final border = Border.all(color: borderColor ?? AppColors.line);

    Widget card = child.padding(
      left: inset.left,
      top: inset.top,
      right: inset.right,
      bottom: inset.bottom,
    );
    if (onTap != null) {
      card = card
          .ripple(
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(seamless ? 0 : kCardRadius),
              ),
            ),
          )
          .gestures(onTap: onTap);
    }
    if (seamless) {
      return card.decorated(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.zero,
      );
    }
    return card
        .clipRRect(all: kCardRadius)
        .decorated(
          color: color ?? AppColors.surface,
          border: border,
          borderRadius: BorderRadius.circular(kCardRadius),
        );
  }
}

/// 包裹状态标签。
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, this.dense = false});

  final ParcelStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (status) {
      ParcelStatus.pending => (AppColors.warn, AppColors.warnSoft),
      ParcelStatus.assigned => (const Color(0xFF1D4ED8), const Color(0xFFDBEAFE)),
      ParcelStatus.inbound => (AppColors.brandDeep, AppColors.brandSoft),
      ParcelStatus.outbound => (const Color(0xFF6D28D9), const Color(0xFFEDE9FE)),
      ParcelStatus.done => (AppColors.ink2, AppColors.surface2),
      ParcelStatus.exception => (AppColors.danger, AppColors.dangerSoft),
    };
    return Text(status.label)
        .textColor(fg)
        .fontSize(dense ? 11 : 12)
        .fontWeight(FontWeight.w600)
        .textStyle(const TextStyle(height: 1.2))
        .padding(horizontal: dense ? 7 : 9, vertical: dense ? 2 : 3)
        .decorated(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        );
  }
}

/// 中性小标签（快递公司、来源等）。
class AppPill extends StatelessWidget {
  const AppPill({super.key, required this.text, this.color = AppColors.ink2});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(text)
        .fontSize(11)
        .fontWeight(FontWeight.w500)
        .textColor(color)
        .padding(horizontal: 8, vertical: 2)
        .decorated(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.line),
        );
  }
}

/// 空状态占位。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description = '',
    this.action,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Icon(icon, size: 28, color: AppColors.ink3)
          .center()
          .constrained(width: 64, height: 64)
          .decorated(color: AppColors.surface2, shape: BoxShape.circle),
      Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.w600)
          .textColor(AppColors.ink)
          .padding(top: 16),
      if (description.isNotEmpty)
        Text(description)
            .fontSize(13)
            .textColor(AppColors.ink3)
            .textStyle(const TextStyle(height: 1.5))
            .textAlignment(TextAlign.center)
            .padding(top: 6),
      if (action != null) action!.padding(top: 16),
    ];
    return Column(mainAxisSize: MainAxisSize.min, children: children)
        .padding(horizontal: 32, vertical: 48)
        .center();
  }
}

/// 区块标题（带可选右侧操作）。
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title)
            .fontSize(14)
            .fontWeight(FontWeight.w600)
            .textColor(AppColors.ink),
        const Spacer(),
        ?trailing,
      ],
    ).padding(left: 4, top: 20, right: 4, bottom: 10);
  }
}

/// 轻提示。
void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
