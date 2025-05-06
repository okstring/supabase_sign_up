import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  await _initializeApp();
  runApp(const MyApp());
}

// 앱 초기화 함수
Future<void> _initializeApp() async {
  await dotenv.load(fileName: ".env");

  final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      autoRefreshToken: true,
      authFlowType: AuthFlowType.implicit,
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: const SignUpPage());
  }
}

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  bool _isSendConfirmCode = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  // 이메일 회원가입 시도 메소드
  Future<void> _signUpWithEmail() async {
    if (_formKey.currentState?.validate() != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await Supabase.instance.client.auth.signUp(
        email: _emailController.text,
        password: _passwordController.text,
      );

      setState(() {
        _isSendConfirmCode = true;
        _isLoading = false;
      });

      _showMessage('인증 이메일이 발송되었습니다. 이메일 확인 후 코드를 입력해주세요.');
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showMessage('회원가입 오류가 발생했습니다: $e');
    }
  }

  // OTP 인증 코드 확인 메소드
  Future<void> _verifyOtpCode() async {
    if (_codeController.text.isEmpty) {
      _showMessage('인증 코드를 입력해주세요.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await Supabase.instance.client.auth.verifyOTP(
        email: _emailController.text,
        token: _codeController.text,
        type: OtpType.signup,
      );

      if (response.session != null && mounted) {
        await _createUserProfile(response);
        _showMessage('회원가입이 완료되었습니다!');
      }
    } catch (e) {
      _showMessage('인증 실패: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 사용자 프로필 생성 (Edge Function 호출)
  Future<void> _createUserProfile(AuthResponse response) async {
    try {
      final invokeUrl = dotenv.env['INVOKE_URL'] ?? '';

      final functionResponse = await _callEdgeFunction(
        invokeUrl: invokeUrl,
        accessToken: response.session!.accessToken,
        userId: response.user!.id,
        userEmail: response.user!.email!,
      );

      _logApiResponse(functionResponse);
    } catch (e) {
      print('사용자 프로필 생성 오류: $e');
      // 프로필 생성 실패해도 회원가입은 성공한 것으로 처리
    }
  }

  // Edge Function API 호출
  Future<http.Response> _callEdgeFunction({
    required String invokeUrl,
    required String accessToken,
    required String userId,
    required String userEmail,
  }) async {
    return await http.post(
      Uri.parse(invokeUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'user': {'id': userId, 'email': userEmail},
      }),
    );
  }

  // API 응답 로깅
  void _logApiResponse(http.Response response) {
    print('상태 코드: ${response.statusCode}');
    print('응답 본문: ${response.body}');
  }

  // 메시지 표시 헬퍼 메소드
  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // 폼 필드 검증
  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return '이메일을 입력해주세요';
    }
    if (!value.contains('@')) {
      return '유효한 이메일 주소를 입력해주세요';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return '비밀번호를 입력해주세요';
    }
    if (value.length < 6) {
      return '비밀번호는 최소 6자 이상이어야 합니다';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('회원가입')),
      body: _buildBody(),
    );
  }

  // 화면 구성 메소드
  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Center(child: SingleChildScrollView(child: _buildForm())),
    );
  }

  // 폼 위젯 구성 메소드
  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '회원가입',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
          ),
          const SizedBox(height: 20),
          _buildEmailField(),
          const SizedBox(height: 16),
          _buildPasswordField(),
          const SizedBox(height: 24),
          _buildSignUpButton(),
          if (_isSendConfirmCode) _buildOtpVerificationSection(),
        ],
      ),
    );
  }

  // 이메일 입력 필드
  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      decoration: const InputDecoration(
        labelText: '이메일',
        border: OutlineInputBorder(),
      ),
      keyboardType: TextInputType.emailAddress,
      validator: _validateEmail,
      enabled: !_isSendConfirmCode,
    );
  }

  // 비밀번호 입력 필드
  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      decoration: const InputDecoration(
        labelText: '비밀번호',
        border: OutlineInputBorder(),
      ),
      obscureText: true,
      validator: _validatePassword,
      enabled: !_isSendConfirmCode,
    );
  }

  // 회원가입 버튼
  Widget _buildSignUpButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isSendConfirmCode || _isLoading ? null : _signUpWithEmail,
        child:
            _isLoading
                ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : const Text('회원가입'),
      ),
    );
  }

  // OTP 인증 섹션
  Widget _buildOtpVerificationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Text(
          '이메일 인증',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _codeController,
          decoration: const InputDecoration(
            labelText: '인증 코드',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _verifyOtpCode,
            child:
                _isLoading
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Text('인증 확인'),
          ),
        ),
      ],
    );
  }
}
