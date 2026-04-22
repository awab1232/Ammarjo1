import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ammar_store/features/store/presentation/pages/main_navigation_page.dart';

const Color _kSplashDark = Color(0xFF1A1A2E);
const Color _kSplashOrange = Color(0xFFFF6B00);

/// سبلاش AmmarJo — ~3 ثوانٍ: مكعبات بناء، اسم، تدرج داكن→برتقالي، شعار، ثم انتقال للرئيسية.
class AmmarJoSplashScreen extends StatefulWidget {
  const AmmarJoSplashScreen({super.key});

  @override
  State<AmmarJoSplashScreen> createState() => _AmmarJoSplashScreenState();
}

class _AmmarJoSplashScreenState extends State<AmmarJoSplashScreen> with TickerProviderStateMixin {
  bool _isDisposed = false;
  late AnimationController _bgController;
  late Animation<Color?> _bgColorAnimation;

  late AnimationController _block1Controller;
  late AnimationController _block2Controller;
  late AnimationController _block3Controller;
  late AnimationController _block4Controller;

  late Animation<double> _block1Slide;
  late Animation<double> _block1Fade;
  late Animation<double> _block2Slide;
  late Animation<double> _block2Fade;
  late Animation<double> _block3Slide;
  late Animation<double> _block3Fade;
  late Animation<double> _block4Slide;
  late Animation<double> _block4Fade;

  late AnimationController _nameController;
  late Animation<double> _nameScale;
  late Animation<double> _nameFade;

  late AnimationController _taglineController;
  late Animation<double> _taglineSlide;
  late Animation<double> _taglineFade;

  late AnimationController _fadeOutController;
  late Animation<double> _fadeOut;

  Listenable get _allAnimations => Listenable.merge([
        _bgController,
        _block1Controller,
        _block2Controller,
        _block3Controller,
        _block4Controller,
        _nameController,
        _taglineController,
        _fadeOutController,
      ]);

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const MainNavigationPage(),
        ),
      );
    });
    _initAnimations();
    _startAnimationSequence();
  }

  void _initAnimations() {
    _bgController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _bgColorAnimation = ColorTween(
      begin: _kSplashDark,
      end: _kSplashOrange,
    ).animate(CurvedAnimation(parent: _bgController, curve: Curves.easeInOut));

    _block1Controller = AnimationController(duration: const Duration(milliseconds: 600), vsync: this);
    _block1Slide = Tween<double>(begin: 60, end: 0).animate(CurvedAnimation(parent: _block1Controller, curve: Curves.easeOut));
    _block1Fade = Tween<double>(begin: 0, end: 1).animate(_block1Controller);

    _block2Controller = AnimationController(duration: const Duration(milliseconds: 600), vsync: this);
    _block2Slide = Tween<double>(begin: 60, end: 0).animate(CurvedAnimation(parent: _block2Controller, curve: Curves.easeOut));
    _block2Fade = Tween<double>(begin: 0, end: 1).animate(_block2Controller);

    _block3Controller = AnimationController(duration: const Duration(milliseconds: 600), vsync: this);
    _block3Slide = Tween<double>(begin: 60, end: 0).animate(CurvedAnimation(parent: _block3Controller, curve: Curves.easeOut));
    _block3Fade = Tween<double>(begin: 0, end: 1).animate(_block3Controller);

    _block4Controller = AnimationController(duration: const Duration(milliseconds: 600), vsync: this);
    _block4Slide = Tween<double>(begin: -60, end: 0).animate(CurvedAnimation(parent: _block4Controller, curve: Curves.easeOut));
    _block4Fade = Tween<double>(begin: 0, end: 1).animate(_block4Controller);

    _nameController = AnimationController(duration: const Duration(milliseconds: 700), vsync: this);
    _nameScale = Tween<double>(begin: 0.5, end: 1).animate(CurvedAnimation(parent: _nameController, curve: Curves.elasticOut));
    _nameFade = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _nameController, curve: Curves.easeIn));

    _taglineController = AnimationController(duration: const Duration(milliseconds: 600), vsync: this);
    _taglineSlide = Tween<double>(begin: 30, end: 0).animate(CurvedAnimation(parent: _taglineController, curve: Curves.easeOut));
    _taglineFade = Tween<double>(begin: 0, end: 1).animate(_taglineController);

    _fadeOutController = AnimationController(duration: const Duration(milliseconds: 400), vsync: this);
    _fadeOut = Tween<double>(begin: 1, end: 0).animate(_fadeOutController);
  }

  /// تأخيرات مضبوطة لمجموع ~3 ثوانٍ (محتوى + خفوت + انتقال).
  Future<void> _startAnimationSequence() async {
    if (!mounted || _isDisposed) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted || _isDisposed) return;

    _block1Controller.forward();
    await Future<void>.delayed(const Duration(milliseconds: 170));
    if (!mounted || _isDisposed) return;
    _block2Controller.forward();
    await Future<void>.delayed(const Duration(milliseconds: 170));
    if (!mounted || _isDisposed) return;
    _block3Controller.forward();
    await Future<void>.delayed(const Duration(milliseconds: 170));
    if (!mounted || _isDisposed) return;
    _block4Controller.forward();
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted || _isDisposed) return;

    _nameController.forward();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted || _isDisposed) return;

    _bgController.forward();
    await Future<void>.delayed(const Duration(milliseconds: 380));
    if (!mounted || _isDisposed) return;

    _taglineController.forward();
    // إبقاء الحالة النهائية ظاهرة ثم خفوت — مجموع التسلسل ~3 ثوانٍ
    await Future<void>.delayed(const Duration(milliseconds: 1090));
    if (!mounted || _isDisposed) return;

    await _fadeOutController.forward();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _bgController.dispose();
    _block1Controller.dispose();
    _block2Controller.dispose();
    _block3Controller.dispose();
    _block4Controller.dispose();
    _nameController.dispose();
    _taglineController.dispose();
    _fadeOutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AnimatedBuilder(
        animation: _allAnimations,
        builder: (context, child) {
          return FadeTransition(
            opacity: _fadeOut,
            child: Scaffold(
              body: Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _bgColorAnimation.value ?? _kSplashDark,
                      Color.lerp(_kSplashDark, const Color(0xFFE65100), _bgController.value) ?? _kSplashDark,
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(flex: 2),
                      _buildBuildingIcon(),
                      const SizedBox(height: 32),
                      Opacity(
                        opacity: _nameFade.value,
                        child: Transform.scale(
                          scale: _nameScale.value,
                          child: Text(
                            'Ammarjo',
                            style: GoogleFonts.cairo(
                              fontSize: 48,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 2,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  offset: const Offset(0, 4),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Opacity(
                        opacity: _nameFade.value,
                        child: Text(
                          'عمارجو',
                          style: GoogleFonts.cairo(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                      const Spacer(flex: 2),
                      Opacity(
                        opacity: _taglineFade.value,
                        child: Transform.translate(
                          offset: Offset(0, _taglineSlide.value),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              'كل ما تحتاجه للبناء في مكان واحد',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.cairo(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.85),
                                height: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 60),
                      Opacity(
                        opacity: _taglineFade.value,
                        child: _buildLoadingDots(),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBuildingIcon() {
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            bottom: 0,
            left: 10,
            child: Opacity(
              opacity: _block1Fade.value,
              child: Transform.translate(
                offset: Offset(0, _block1Slide.value),
                child: Container(
                  width: 35,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 10,
            child: Opacity(
              opacity: _block2Fade.value,
              child: Transform.translate(
                offset: Offset(0, _block2Slide.value),
                child: Container(
                  width: 35,
                  height: 55,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 25,
            child: Opacity(
              opacity: _block3Fade.value,
              child: Transform.translate(
                offset: Offset(0, _block3Slide.value),
                child: Container(
                  width: 50,
                  height: 35,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            child: Opacity(
              opacity: _block4Fade.value,
              child: Transform.translate(
                offset: Offset(0, _block4Slide.value),
                child: CustomPaint(
                  size: const Size(60, 30),
                  painter: _RoofPainter(),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 8,
            left: 17,
            child: Opacity(
              opacity: _block1Fade.value,
              child: Container(
                width: 10,
                height: 10,
                color: _kSplashOrange,
              ),
            ),
          ),
          Positioned(
            bottom: 8,
            right: 17,
            child: Opacity(
              opacity: _block2Fade.value,
              child: Container(
                width: 10,
                height: 10,
                color: _kSplashOrange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final delay = i * 0.25;
        final progress = (_taglineController.value - delay).clamp(0.0, 1.0);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: progress > 0 ? 0.8 : 0.25),
          ),
        );
      }),
    );
  }
}

class _RoofPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _RoofPainter oldDelegate) => false;
}
