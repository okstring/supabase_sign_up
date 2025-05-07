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

## CORS 포함 Edge Function Code

```typescript
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
// 허용할 오리진 목록
const ALLOWED_ORIGINS = [
  "*" // 모든 오리진 허용 (개발 중에만 사용)
];
// CORS 헤더 설정
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': '*',
  'Access-Control-Max-Age': '86400',
  'Access-Control-Allow-Credentials': 'true' // 인증 정보 허용
};
// 인증 웹훅 처리 함수
Deno.serve(async (req)=>{
  // CORS 프리플라이트 요청 처리
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      status: 204,
      headers: corsHeaders
    });
  }
  // 요청이 POST 메서드인지 확인
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({
      error: 'Method not allowed'
    }), {
      status: 405,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      }
    });
  }
  try {
    // 요청 본문 파싱
    const bodyText = await req.text();
    let payload;
    try {
      payload = JSON.parse(bodyText);
    } catch (e) {
      return new Response(JSON.stringify({
        error: 'Invalid JSON'
      }), {
        status: 400,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }
    // Supabase 클라이언트 초기화
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    if (!supabaseUrl || !supabaseServiceKey) {
      return new Response(JSON.stringify({
        error: '서버 구성 오류: 환경 변수가 설정되지 않았습니다.'
      }), {
        status: 500,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }
    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    // 사용자 정보 추출
    let userId, userEmail;
    if (payload.user) {
      userId = payload.user.id;
      userEmail = payload.user.email;
    } else if (payload.data) {
      userId = payload.data.id;
      userEmail = payload.data.email;
    }
    // 사용자 정보 검증
    if (!userId || !userEmail) {
      return new Response(JSON.stringify({
        error: '사용자 정보를 찾을 수 없습니다.'
      }), {
        status: 400,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }
    // 사용자 이름 생성
    const userName = userEmail.split('@')[0];
    // users 테이블에 이미 해당 사용자가 있는지 확인
    const { data: existingUser, error: fetchError } = await supabase.from('users').select('user_id').eq('user_id', userId).single();
    if (fetchError && fetchError.code !== 'PGRST116') {
      return new Response(JSON.stringify({
        error: fetchError.message
      }), {
        status: 500,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }
    // 이미 사용자가 있다면 추가 작업을 하지 않음
    if (existingUser) {
      return new Response(JSON.stringify({
        success: true,
        message: '이미 등록된 사용자입니다.'
      }), {
        status: 200,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }
    // public.users 테이블에 데이터 삽입
    const { error: usersError } = await supabase.from('users').insert({
      user_id: userId,
      user_name: userName
    });
    if (usersError) {
      return new Response(JSON.stringify({
        error: usersError.message
      }), {
        status: 500,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }
    // public.user_private 테이블에 데이터 삽입
    const { error: userPrivateError } = await supabase.from('user_private').insert({
      user_id: userId,
      user_email: userEmail
    });
    if (userPrivateError) {
      // user_private 삽입 실패 시 users 테이블 롤백
      await supabase.from('users').delete().eq('user_id', userId);
      return new Response(JSON.stringify({
        error: userPrivateError.message
      }), {
        status: 500,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json'
        }
      });
    }
    // 성공 응답
    return new Response(JSON.stringify({
      success: true,
      message: '사용자 등록 완료'
    }), {
      status: 200,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      }
    });
  } catch (error) {
    return new Response(JSON.stringify({
      error: String(error)
    }), {
      status: 500,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      }
    });
  }
});

```

## 주의사항

- Flutter Web에서 특히 CORS 문제가 발생할 수 있음
- Edge Function은 환경 변수로 보안 키 관리
- Supabase에서 Enforce JWT Verification 비활성화
- `assets/.env` 에 환경변수 기입 