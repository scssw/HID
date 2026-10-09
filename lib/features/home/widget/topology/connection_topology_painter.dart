import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hiddify/features/home/widget/topology/connection_topology_model.dart';

class ConnectionTopologyPainter extends CustomPainter {
  final TopoLayoutResult layout;
  final Set<String>? highlightedIds;
  final double animationProgress;
  final bool isDark;
  final String colDeviceLabel;
  final String colTargetLabel;
  final String colOutboundLabel;

  const ConnectionTopologyPainter({
    required this.layout,
    this.highlightedIds,
    required this.animationProgress,
    required this.isDark,
    required this.colDeviceLabel,
    required this.colTargetLabel,
    required this.colOutboundLabel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (layout.nodes.isEmpty) return;

    final fgColor = isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B);
    final faintColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    // 1. Column headers (clamped for mobile screens)
    final deviceCx = (size.width * colXSource).clamp(24.0, size.width * 0.25);
    final outboundCx = (size.width * colXOutbound).clamp(size.width * 0.75, size.width - 24.0);
    _drawColumnHeader(canvas, colDeviceLabel, deviceCx, 10, faintColor);
    _drawColumnHeader(canvas, colTargetLabel, size.width * colXHost, 10, faintColor);
    _drawColumnHeader(canvas, colOutboundLabel, outboundCx, 10, faintColor);

    final dividerY = layout.dividerY > 0 ? layout.dividerY : size.height * 0.5;

    // 2. Zone Badges and Divider Line (clamped for mobile)
    final badgeX = (size.width * colXSource - 40.0).clamp(8.0, size.width * 0.25);
    if (layout.expandedZone == null) {
      // Upper Zone Badge (代理)
      _drawZoneBadge(
        canvas,
        '▲ 代理流向',
        Offset(badgeX, 24),
        isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1),
      );

      // Middle Divider Line
      final dividerPaint = Paint()
        ..color = (isDark ? Colors.white : Colors.black).withOpacity(0.08)
        ..strokeWidth = 1.0;
      canvas.drawLine(Offset(12, dividerY), Offset(size.width - 12, dividerY), dividerPaint);

      // Lower Zone Badge (直连)
      _drawZoneBadge(
        canvas,
        '▼ 直连流向',
        Offset(badgeX, dividerY + 6),
        isDark ? const Color(0xFF00E5FF) : const Color(0xFF0D9488),
      );
    } else {
      // Expanded single zone banner
      final isProxy = layout.expandedZone == 'proxy';
      final zoneName = isProxy ? '代理' : '直连';
      _drawZoneBadge(
        canvas,
        '🔍 $zoneName流向全屏展示 · 双击域名或空白处恢复分栏',
        Offset(badgeX, 24),
        isProxy
            ? (isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1))
            : (isDark ? const Color(0xFF00E5FF) : const Color(0xFF0D9488)),
      );
    }

    // 3. Ribbons (Sankey Links)
    for (final link in layout.links) {
      final isHl = highlightedIds?.contains(link.id) ?? false;
      final opacity = (highlightedIds != null && highlightedIds!.isNotEmpty)
          ? (isHl ? 0.95 : 0.28)
          : 0.72; // Bright default!

      final bounds = link.path.getBounds();
      final shader = LinearGradient(
        colors: [
          link.sourceColor.withOpacity(opacity),
          link.targetColor.withOpacity(opacity),
        ],
      ).createShader(bounds);

      final paint = Paint()
        ..shader = shader
        ..style = PaintingStyle.fill;

      canvas.drawPath(link.path, paint);

      if (isHl) {
        final strokePaint = Paint()
          ..color = link.targetColor.withOpacity(0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawPath(link.path, strokePaint);
      }
    }

    // 4. Flowing particles along the exact Bezier curve ribbons (blue & green streams)
    _drawFlowParticles(canvas, size);

    // 5. Nodes and labels
    for (final node in layout.nodes) {
      final isHl = highlightedIds?.contains(node.id) ?? false;
      final opacity = (highlightedIds != null && highlightedIds!.isNotEmpty)
          ? (isHl ? 1.0 : 0.45)
          : 1.0;

      if (node.type == TopoNodeType.host) {
        // --- Domain Node: Centered Pill ---
        final rrect = RRect.fromRectAndRadius(node.rect, const Radius.circular(4.0));

        // Pill background
        final bgPaint = Paint()
          ..color = isDark
              ? const Color(0xFF1E222D).withOpacity(0.85)
              : Colors.white.withOpacity(0.92)
          ..style = PaintingStyle.fill;
        canvas.drawRRect(rrect, bgPaint);

        // Pill border
        final borderPaint = Paint()
          ..color = isHl
              ? (isDark ? Colors.white : Colors.black).withOpacity(0.9)
              : node.color.withOpacity(0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isHl ? 1.6 : 1.0;
        canvas.drawRRect(rrect, borderPaint);

        // Text inside pill (centered horizontally and vertically)
        final textSpan = TextSpan(
          text: node.name,
          style: TextStyle(
            color: fgColor.withOpacity(opacity * 0.95),
            fontSize: 10.0,
            fontWeight: isHl ? FontWeight.w600 : FontWeight.w500,
          ),
        );
        final maxTextW = node.width - (node.recent ? 18.0 : 8.0);
        final tp = TextPainter(
          text: textSpan,
          maxLines: 1,
          ellipsis: '…',
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: maxTextW);

        final tx = node.x + (node.width - tp.width) / 2 + (node.recent ? 4.0 : 0.0);
        final ty = node.y + (node.height - tp.height) / 2;
        tp.paint(canvas, Offset(tx, ty));

        // Recent dot mark inside the pill on the left
        if (node.recent) {
          final markPaint = Paint()
            ..color = const Color(0xFF00E5FF).withOpacity(opacity)
            ..style = PaintingStyle.fill;
          canvas.drawCircle(Offset(node.x + 6.0, node.y + node.height / 2), 2.0, markPaint);
        }
      } else {
        // --- Source or Outbound Node: Vertical Bar ---
        final rrect = RRect.fromRectAndRadius(node.rect, const Radius.circular(3.0));
        final barPaint = Paint()
          ..color = node.color.withOpacity(opacity)
          ..style = PaintingStyle.fill;
        canvas.drawRRect(rrect, barPaint);

        if (isHl) {
          final ringPaint = Paint()
            ..color = (isDark ? Colors.white : Colors.black).withOpacity(0.95)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5;
          canvas.drawRRect(rrect, ringPaint);
        }

        // Draw side label for source/outbound
        _drawBarLabel(canvas, node, fgColor, opacity);
      }
    }
  }

  void _drawZoneBadge(Canvas canvas, String text, Offset offset, Color color) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: color.withOpacity(0.9),
        fontSize: 10.5,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.3,
      ),
    );
    final tp = TextPainter(
      text: textSpan,
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  void _drawColumnHeader(Canvas canvas, String text, double cx, double y, Color color) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: 11.0,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );
    final tp = TextPainter(
      text: textSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(canvas, Offset(cx - tp.width / 2, y));
  }

  void _drawBarLabel(Canvas canvas, TopoNode node, Color color, double opacity) {
    final isLeft = node.type == TopoNodeType.source;
    final maxW = isLeft ? math.max(28.0, node.x - 4.0) : 120.0;

    final label = node.name;
    final textSpan = TextSpan(
      text: label,
      style: TextStyle(
        color: color.withOpacity(opacity),
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
      ),
    );

    final tp = TextPainter(
      text: textSpan,
      maxLines: 1,
      ellipsis: '…',
      textAlign: isLeft ? TextAlign.right : TextAlign.left,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxW);

    final double lx = isLeft ? math.max(2.0, node.x - tp.width - 5.0) : (node.x + node.width + 5.0);
    final double ly = node.y + (node.height - tp.height) / 2;

    tp.paint(canvas, Offset(lx, ly));
  }

  void _drawFlowParticles(Canvas canvas, Size size) {
    if (layout.links.isEmpty) return;

    for (var i = 0; i < layout.links.length; i++) {
      final link = layout.links[i];
      if (layout.expandedZone != null && link.zone != layout.expandedZone) continue;

      // Stagger particles across links
      final t = (animationProgress + (i * 0.17)) % 1.0;

      final x0 = link.sourceX;
      final y0 = link.sourceY + link.heightSource / 2;
      final x1 = link.targetX;
      final y1 = link.targetY + link.heightTarget / 2;
      final xi = (x0 + x1) / 2;

      // Exact cubic bezier curve centerline interpolation
      final oneMinusT = 1.0 - t;
      final px = oneMinusT * oneMinusT * oneMinusT * x0 +
          3.0 * oneMinusT * oneMinusT * t * xi +
          3.0 * oneMinusT * t * t * xi +
          t * t * t * x1;
      final py = oneMinusT * oneMinusT * oneMinusT * y0 +
          3.0 * oneMinusT * oneMinusT * t * y0 +
          3.0 * oneMinusT * t * t * y1 +
          t * t * t * y1;

      final particleColor = Color.lerp(link.sourceColor, link.targetColor, t) ?? link.targetColor;

      // Outer glow
      final glowPaint = Paint()
        ..color = particleColor.withOpacity(0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
      canvas.drawCircle(Offset(px, py), 4.0, glowPaint);

      // Inner bright particle
      final corePaint = Paint()
        ..color = Colors.white.withOpacity(0.95)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(px, py), 2.2, corePaint);
    }
  }

  @override
  bool shouldRepaint(covariant ConnectionTopologyPainter oldDelegate) {
    return oldDelegate.animationProgress != animationProgress ||
        oldDelegate.highlightedIds != highlightedIds ||
        oldDelegate.isDark != isDark ||
        oldDelegate.layout != layout;
  }
}
