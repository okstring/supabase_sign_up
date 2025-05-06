# Supabase 회원가입 프로세스 요약

## 기본 흐름

1. **회원가입 요청**: 사용자가 이메일/비밀번호 입력 → Supabase Auth API 요청
2. **이메일 인증**: 인증 코드 발송 → 사용자 입력 → OTP 검증 → 세션 및 토큰 발급
3. **사용자 정보 저장**: 클라이언트에서 Edge Function 호출 → 커스텀 테이블에 데이터 저장

## Edge Function 중요성

- **권한 분리**: 클라이언트에서 직접 DB 접근 없이 제어된 방식으로 데이터 관리
- **보안 강화**: 서비스 롤 키는 Edge Function 내부에만 존재
- **비즈니스 로직 중앙화**: 데이터 검증, 변환, 저장 로직을 한 곳에서 관리
- **트랜잭션 처리**: 여러 테이블에 데이터 삽입 실패 시 롤백 가능

## CORS 설정 (⚠️ 중요)

```typescript
// Edge Function 내 CORS 헤더 필수 설정
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',  // 프로덕션 환경에서는 특정 도메인으로 제한 권장
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': '*',  // 모든 헤더 허용
  'Access-Control-Max-Age': '86400',
  'Access-Control-Allow-Credentials': 'true'
};

// OPTIONS 요청 처리 (프리플라이트)
if (req.method === 'OPTIONS') {
  return new Response(null, {
    status: 204,
    headers: corsHeaders
  });
}

// 모든 응답에 CORS 헤더 포함
return new Response(JSON.stringify(data), {
  status: 200,
  headers: { ...corsHeaders, 'Content-Type': 'application/json' }
});
```

## 주의사항

- Flutter Web에서 특히 CORS 문제가 발생할 수 있음
- Edge Function은 환경 변수로 보안 키 관리