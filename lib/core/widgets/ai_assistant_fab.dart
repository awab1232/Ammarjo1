import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

class AiAssistantFab extends StatefulWidget {
  const AiAssistantFab({
    super.key,
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  State<AiAssistantFab> createState() => _AiAssistantFabState();
}

class _AiAssistantFabState extends State<AiAssistantFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    HapticFeedback.mediumImpact();
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Tooltip(
        message: 'المساعد الذكي',
        textStyle: GoogleFonts.tajawal(color: Colors.white, fontSize: 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryOrange.withValues(alpha: 0.32),
                blurRadius: 20,
                spreadRadius: 3,
              ),
            ],
          ),
          child: FloatingActionButton(
            heroTag: 'ai_assistant_fab',
            onPressed: _handleTap,
            elevation: 0,
            backgroundColor: Colors.transparent,
            splashColor: AppColors.orangeLight.withValues(alpha: 0.4),
            child: Ink(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    Color(0xFFFFB347),
                    AppColors.primaryOrange,
                  ],
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.psychology_alt_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                  Positioned(
                    top: 11,
                    right: 13,
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white.withValues(alpha: 0.95),
                      size: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

