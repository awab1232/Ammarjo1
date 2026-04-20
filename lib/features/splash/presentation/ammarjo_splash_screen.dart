import 'package:flutter/material.dart';

class AmmarJoSplashScreen extends StatefulWidget {
  const AmmarJoSplashScreen({super.key});

  @override
  State<AmmarJoSplashScreen> createState() => _AmmarJoSplashScreenState();
}

class _AmmarJoSplashScreenState extends State<AmmarJoSplashScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: SizedBox());
  }
}
